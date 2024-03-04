(module
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; imports from JS
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (import "game" "onGameOver" (func $onGameOver))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; Classic Snake in WebAssembly text format
  ;;
  ;; Memory layout:
  ;;
  ;; One virtual page in WASM is 64kb. We will need 3 pages to hold all of the data (pixel buffer + characters + game state).
  ;; 64kb * 3 pages = 192kb = 196608 bytes for the entire program
  ;;  ______________________________________________________________________________________________________________________________________
  ;; | Offset:                                    |                                      |                                                 |
  ;; | index 0                                    | index 37500                          | index 40000                                     |
  ;; | byte index 0                               | byte index 150000                    | byte index 160000                               |
  ;; |--------------------------------------------|--------------------------------------|-------------------------------------------------|
  ;; | VRAM (pixel buffer contents)               | Char encodings (64 pixels per char)  | Snake parts positions (max 300)                 |
  ;; | 256px width * 144 px height = 36864 pixels | Chars: 0123456789GAMEOVER            | Each position has 2 coords (XY)                 |
  ;; | 4 bytes per pixel = 147456 bytes           | 64 * 18 chars * 4 bytes = 4608 bytes | 300 positions * 2 coords * 4 bytes = 2400 bytes |
  ;; |____________________________________________|______________________________________|_________________________________________________|
  ;; 
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (memory 3)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; global vars
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (global $screenWidth i32 (i32.const 256))
  (global $screenHeight i32 (i32.const 144))
  (global $gameGridHeight i32 (i32.const 128))
  (global $vramPixelCount i32 (i32.const 36864))        ;; screenWidth * screenHeight

  (global $topPadding i32 (i32.const 16))
  (global $bottomPadding i32 (i32.const 4))
  (global $rightPadding i32 (i32.const 4))
  (global $leftPadding i32 (i32.const 4))
  
  (global $snakeMoveState (mut i32) (i32.const 0))     ;; 0 - top ;; 1 - right ;; 2 - bottom ;; 3 - left ;;
  (global $snakePartsCounter (mut i32) (i32.const 0))
  (global $snakePartsByteOffset i32 (i32.const 160000))

  (global $charsByteOffset i32 (i32.const 150000))
  (global $charWidth i32 (i32.const 8))
  (global $charPixelSize i32 (i32.const 64))

  (global $score (mut i32) (i32.const 0))
  (global $scoreIncrement (mut i32) (i32.const 16))
  (global $frameCounter (mut i32) (i32.const 0))

  (global $isGameOver (mut i32) (i32.const 0))
  (global $gameOverOffsetX (mut i32) (i32.const 0))
  (global $gameOverOffsetY (mut i32) (i32.const 0))
  (global $gameOverVelX (mut i32) (i32.const 5))
  (global $gameOverVelY (mut i32) (i32.const 2))

  (global $foodX (mut i32) (i32.const 0))
  (global $foodY (mut i32) (i32.const 0))
  (global $foodColorState (mut i32) (i32.const 0))

  (global $randomState (mut i64) (i64.const 0x853c49e6748fea9b))
  (global $randomSequence (mut i64) (i64.const 0xda3e39cb94b95bdb))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; exports (visible from JS)
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (export "memory" (memory 0))
  (export "start" (func $main))
  (export "updateFrame" (func $updateFrame))
  (export "setSnakeMovementState" (func $setSnakeMovementState))
  (export "setCharDataAtIdx" (func $setCharDataAtIdx))
  (export "setDifficulty" (func $setDifficulty))
  (export "refreshGame" (func $refreshGame))
  (export "randomState" (global $randomState))
  (export "randomSequence" (global $randomSequence))
  (export "randomInt32" (func $random_int_32))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; PCG-32 random number generator
  ;; https://github.com/alisey/pcg32
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $random_int_32 (result i32)
    (local $old_state i64)

    ;; uint64_t old_state = state;
    ;; randomState = old_state * 6364136223846793005ULL + randomSequence;
    (global.set $randomState
      (i64.add
        (i64.mul
          (local.tee $old_state
            (global.get $randomState)
          )
          (i64.const 0x5851f42d4c957f2d)
        )
        (global.get $randomSequence)
      )
    )

    ;; return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
    ;; Rotates `xorshifted` right by `rot` bits.
    (i32.rotr
      ;; uint32_t xorshifted = ((old_state >> 18u) ^ old_state) >> 27u;
      (i32.wrap_i64
        (i64.shr_u
          (i64.xor
            (i64.shr_u
              (local.get $old_state)
              (i64.const 18)
            )
            (local.get $old_state)
          )
          (i64.const 27)
        )
      )
      ;; uint32_t rot = old_state >> 59u;
      (i32.wrap_i64
        (i64.shr_u
          (local.get $old_state)
          (i64.const 59)
        )
      )
    )
  )

  (func $random_int (param $bound i32) (result i32)
    (local $random    i32)
    (local $threshold i32)

    ;; uint32_t threshold = -bound % bound;
    (local.set $threshold
      (i32.rem_u
        (i32.sub
          (i32.const 0)
          (local.get $bound)
        )
        (local.get $bound)
      )
    )

    ;; for (;;) {
    ;;     uint32_t random = pcg32_random();
    ;;     if (random < threshold) continue;
    ;;     break;
    ;; }
    (loop $try_random
      (br_if $try_random
          (i32.lt_u
            (local.tee $random (call $random_int_32))
            (local.get $threshold)
          )
      )
    )

    ;; return random % bound;
    (i32.rem_u
      (local.get $random)
      (local.get $bound)
    )
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; drawing utilities
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $putPixelAtIdx (param $idx i32) (param $color i32)
    local.get $idx
    i32.const 4 ;; 4 bytes per i32
    i32.mul
    local.get $color
    i32.store
  )

  (func $putPixelAtXY (param $x i32) (param $y i32) (param $color i32)
    (local $idx i32)
    ;; calculate idx based on x, y
    local.get $y
    global.get $screenWidth
    i32.mul
    local.get $x
    i32.add
    ;; store color in memory
    local.get $color
    call $putPixelAtIdx
  )

  (func $clearBackground
    (local $i i32)
    (local.set $i (global.get $vramPixelCount))
    (loop $clearBgLoop
      local.get $i
      i32.const 20
      call $putPixelAtIdx

      local.get $i
      i32.const 1
      i32.sub
      local.tee $i

      i32.const -1
      i32.ne
      (br_if $clearBgLoop)
    )
  )

  (func $drawSnakeBlock (param $x i32) (param $y i32) (param $isHead i32)
    (local $xStart i32)
    (local $yStart i32)
    (local $xEnd i32)
    (local $yEnd i32)
    (local $eyeX i32)
    (local $eyeY i32)

    local.get $x
    i32.const 1
    i32.add
    local.tee $xStart
    local.set $x

    local.get $y
    i32.const 1
    i32.add
    local.tee $yStart
    local.set $y

    ;; calc xEnd
    local.get $x
    i32.const 7
    i32.add
    local.set $xEnd

    ;; calc yEnd
    local.get $y
    i32.const 7
    i32.add
    local.set $yEnd

    (loop $xLoop
      (loop $yLoop

        ;; draw pixel within block
        local.get $x
        local.get $y
        i32.const 255
        call $putPixelAtXY

        
        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        local.get $yEnd
        i32.lt_u
        (br_if $yLoop)
      )
      ;; reset y to equal yStart
      local.get $yStart
      local.set $y

      
      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xEnd
      i32.lt_u
      (br_if $xLoop)
    )

    ;; draw eyes
    local.get $isHead
    i32.const 1
    i32.eq
    (if
      (then
        local.get $xStart
        i32.const 3
        i32.add
        local.set $eyeX

        local.get $yStart
        i32.const 3
        i32.add
        local.set $eyeY

        local.get $eyeX
        local.get $eyeY
        i32.const 0
        call $putPixelAtXY
      )
    )        
  )

  (func $drawChar (param $charIdx i32) (param $offsetX i32) (param $offsetY i32) (param $color i32)
    (local $charByteOffset i32)
    (local $loopIdx i32)
    (local $charPixelLocalX i32)
    (local $charPixelLocalY i32)
    (local $charPixelWorldX i32)
    (local $charPixelWorldY i32)
    (local $charByte i32)
    
    local.get $charIdx
    global.get $charPixelSize
    i32.mul
    i32.const 4
    i32.mul
    global.get $charsByteOffset
    i32.add
    local.set $charByteOffset

    i32.const 0
    local.set $loopIdx

    (loop $charDrawLoop
      ;; calculate char pixel byte value
      local.get $loopIdx
      i32.const 4
      i32.mul
      local.get $charByteOffset
      i32.add
      i32.load
      local.set $charByte

      ;; calculate char pixel x and y
      local.get $loopIdx
      global.get $charWidth
      i32.rem_u
      local.tee $charPixelLocalX
      local.get $offsetX
      i32.add
      local.set $charPixelWorldX

      local.get $loopIdx
      global.get $charWidth
      i32.div_u
      local.tee $charPixelLocalY
      local.get $offsetY
      i32.add
      local.set $charPixelWorldY

      local.get $charByte
      i32.const 0
      i32.ne
      (if
        (then
          local.get $charPixelWorldX
          local.get $charPixelWorldY
          local.get $color
          call $putPixelAtXY 
        )
      )

      local.get $loopIdx
      i32.const 1
      i32.add
      local.tee $loopIdx
      global.get $charPixelSize
      i32.ne
      br_if $charDrawLoop
    )
  )

  (func $drawScore
    (local $i i32)
    (local $iValue i32)
    (local $xOffset i32)

    (local $localScore i32)
    (local $digit0 i32)
    (local $digit1 i32)
    (local $digit2 i32)
    (local $digit3 i32)
    (local $digit4 i32)
    (local $digit5 i32)

    global.get $score
    local.tee $localScore

    i32.const 10
    i32.rem_u
    local.set $digit5

    local.get $localScore
    i32.const 10
    i32.div_u
    local.set $localScore

    local.get $localScore
    i32.const 10
    i32.rem_u
    local.set $digit4

    local.get $localScore
    i32.const 10
    i32.div_u
    local.set $localScore
    
    local.get $localScore
    i32.const 10
    i32.rem_u
    local.set $digit3

    local.get $localScore
    i32.const 10
    i32.div_u
    local.set $localScore

    local.get $localScore
    i32.const 10
    i32.rem_u
    local.set $digit2

    local.get $localScore
    i32.const 10
    i32.div_u
    local.set $localScore

    local.get $localScore
    i32.const 10
    i32.rem_u
    local.set $digit1

    local.get $localScore
    i32.const 10
    i32.div_u
    local.set $localScore

    local.get $localScore
    i32.const 10
    i32.rem_u
    local.set $digit0
    
    global.get $leftPadding
    local.set $xOffset

    local.get $digit0
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit1
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit2
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit3
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit4
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit5
    local.get $xOffset
    i32.const 3
    i32.const 255
    call $drawChar
  )

  (func $drawDebugGrid
    (local $x i32)
    (local $y i32)
    
    i32.const 0
    local.set $x
    (loop $drawXGrid

      global.get $topPadding
      local.set $y
      (loop $drawLine
        local.get $x
        local.get $y
        i32.const 25
        call $putPixelAtXY

        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        global.get $screenHeight
        i32.ne
        (br_if $drawLine)
      )
    
      local.get $x
      i32.const 8
      i32.add
      local.tee $x
      global.get $screenWidth
      i32.ne
      (br_if $drawXGrid)
    )

    global.get $topPadding
    local.set $y
    (loop $drawYGrid

      i32.const 0
      local.set $x
      (loop $drawLine
        local.get $x
        local.get $y
        i32.const 25
        call $putPixelAtXY

        local.get $x
        i32.const 1
        i32.add
        local.tee $x
        global.get $screenWidth
        i32.ne
        (br_if $drawLine)
      )
    
      local.get $y
      i32.const 8
      i32.add
      local.tee $y
      global.get $screenHeight
      i32.ne
      (br_if $drawYGrid)
    )
  )

  (func $drawBorder
    (local $x i32)
    (local $y i32)
    (local $xStart i32)
    (local $xEnd i32)
    (local $yStart i32)
    (local $yEnd i32)

    global.get $screenWidth
    global.get $rightPadding
    i32.sub
    local.set $xEnd

    global.get $leftPadding
    local.tee $x
    local.set $xStart

    ;; draw top border
    (loop $topBorderLoop
      local.get $x
      global.get $topPadding
      i32.const 255
      call $putPixelAtXY

      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xEnd
      i32.ne
      (br_if $topBorderLoop)
    )
    local.get $xStart
    local.set $x
  )

  (func $drawFood
    ;; (local $xBlockStart i32)
    (local $yBlockStart i32)
    (local $xBlockEnd i32)
    (local $yBlockEnd i32)
    (local $xStart i32)
    (local $yStart i32)
    (local $topColor i32)
    (local $rightColor i32)
    (local $bottomColor i32)
    (local $leftColor i32)
    (local $x i32)
    (local $y i32)

    global.get $foodX
    local.set $x
    global.get $foodY
    local.set $y

    global.get $frameCounter
    i32.const 5
    i32.rem_u
    (if
      (then)
      (else
        global.get $foodColorState
        i32.const 1
        i32.add
        global.set $foodColorState
        global.get $foodColorState
        i32.const 4
        i32.eq
        (if
          (then
            i32.const 0
            global.set $foodColorState
          )
        )
      )
    )

    global.get $foodColorState
    i32.eqz
    (if
      (then
        i32.const 200
        local.set $topColor
        i32.const 150
        local.set $rightColor
        i32.const 100
        local.set $bottomColor
        i32.const 75
        local.set $leftColor
      )
    )

    global.get $foodColorState
    i32.const 1
    i32.eq
    (if
      (then
        i32.const 75
        local.set $topColor
        i32.const 200
        local.set $rightColor
        i32.const 150
        local.set $bottomColor
        i32.const 100
        local.set $leftColor
      )
    )

    global.get $foodColorState
    i32.const 2
    i32.eq
    (if
      (then
        i32.const 100
        local.set $topColor
        i32.const 75
        local.set $rightColor
        i32.const 200
        local.set $bottomColor
        i32.const 150
        local.set $leftColor
      )
    )

    global.get $foodColorState
    i32.const 3
    i32.eq
    (if
      (then
        i32.const 150
        local.set $topColor
        i32.const 100
        local.set $rightColor
        i32.const 75
        local.set $bottomColor
        i32.const 200
        local.set $leftColor
      )
    )

    local.get $x
    local.tee $xStart
    i32.const 3
    i32.add
    ;; local.tee $xBlockStart
    local.tee $x
    i32.const 3
    i32.add
    local.set $xBlockEnd

    local.get $y
    i32.const 1
    i32.add
    local.tee $yStart
    local.tee $yBlockStart
    i32.const 2
    i32.add
    local.set $yBlockEnd

    ;; draw top block
    (loop $topBlockLoopX
      local.get $yBlockStart
      local.set $y
      (loop $topBlockLoopY
        local.get $x
        local.get $y
        local.get $topColor
        call $putPixelAtXY

        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        local.get $yBlockEnd
        i32.ne
        (br_if $topBlockLoopY)
      )
    
      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xBlockEnd
      i32.ne
      (br_if $topBlockLoopX)
    )

    ;; draw right block
    local.get $xStart
    i32.const 6
    i32.add
    local.set $x

    local.get $xStart
    i32.const 8
    i32.add
    local.set $xBlockEnd

    local.get $yStart
    i32.const 2
    i32.add
    local.tee $y
    local.set $yBlockStart

    local.get $yStart
    i32.const 5
    i32.add
    local.set $yBlockEnd

    (loop $rightBlockLoopX
      local.get $yBlockStart
      local.set $y
      (loop $rightBlockLoopY
        local.get $x
        local.get $y
        local.get $rightColor
        call $putPixelAtXY

        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        local.get $yBlockEnd
        i32.ne
        (br_if $rightBlockLoopY)
      )
    
      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xBlockEnd
      i32.ne
      (br_if $rightBlockLoopX)
    )

    ;; draw bottom block
    local.get $xStart
    i32.const 3
    i32.add
    local.set $x

    local.get $xStart
    i32.const 6
    i32.add
    local.set $xBlockEnd

    local.get $yStart
    i32.const 5
    i32.add
    local.tee $y
    local.set $yBlockStart

    local.get $yStart
    i32.const 7
    i32.add
    local.set $yBlockEnd

    (loop $bottomBlockLoopX
      local.get $yBlockStart
      local.set $y
      (loop $bottomBlockLoopY
        local.get $x
        local.get $y
        local.get $bottomColor
        call $putPixelAtXY

        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        local.get $yBlockEnd
        i32.ne
        (br_if $bottomBlockLoopY)
      )
    
      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xBlockEnd
      i32.ne
      (br_if $bottomBlockLoopX)
    )

    ;; draw left block
    local.get $xStart
    i32.const 1
    i32.add
    local.set $x

    local.get $xStart
    i32.const 3
    i32.add
    local.set $xBlockEnd

    local.get $yStart
    i32.const 2
    i32.add
    local.tee $y
    local.set $yBlockStart

    local.get $yStart
    i32.const 5
    i32.add
    local.set $yBlockEnd

    (loop $leftBlockLoopX
      local.get $yBlockStart
      local.set $y
      (loop $leftBlockLoopY
        local.get $x
        local.get $y
        local.get $leftColor
        call $putPixelAtXY

        local.get $y
        i32.const 1
        i32.add
        local.tee $y
        local.get $yBlockEnd
        i32.ne
        (br_if $leftBlockLoopY)
      )
    
      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xBlockEnd
      i32.ne
      (br_if $leftBlockLoopX)
    )
    
  )

  (func $drawSnake
    (local $partIdx i32)
    (local $partByteOffset i32)
    (local $partX i32)
    (local $partY i32)
    (local $isHead i32)

    i32.const 0
    local.set $partIdx

    (loop $drawSnakeBlocksLoop

      local.get $partIdx
      i32.eqz
      local.set $isHead

      local.get $partIdx
      i32.const 8
      i32.mul
      global.get $snakePartsByteOffset
      i32.add
      local.tee $partByteOffset
      i32.load
      local.set $partX

      local.get $partByteOffset
      i32.const 4
      i32.add
      i32.load
      local.set $partY
      
      local.get $partX
      local.get $partY
      local.get $isHead
      call $drawSnakeBlock

      local.get $partIdx
      i32.const 1
      i32.add
      local.tee $partIdx
      global.get $snakePartsCounter
      i32.ne
      (br_if $drawSnakeBlocksLoop)
    )
  )

  (func $drawGameOver
    (local $topLeftY i32)
    (local $width i32)
    (local $halfWidth i32)
    (local $height i32)
    (local $halfHeight i32)
    (local $offsetX i32)

    i32.const 86
    local.set $width
    i32.const 43
    local.set $halfWidth

    i32.const 8
    local.set $height
    i32.const 4
    local.set $halfHeight

    global.get $gameOverOffsetX
    global.get $gameOverVelX
    i32.add
    global.set $gameOverOffsetX

    global.get $gameOverOffsetY
    global.get $gameOverVelY
    i32.add
    global.set $gameOverOffsetY

    global.get $screenWidth
    i32.const 2
    i32.div_u
    local.get $halfWidth
    i32.sub
    local.tee $offsetX
    global.get $gameOverOffsetX
    i32.add
    local.set $offsetX

    global.get $screenHeight
    i32.const 2
    i32.div_u
    local.get $halfHeight
    i32.sub
    local.tee $topLeftY
    global.get $gameOverOffsetY
    i32.add
    local.set $topLeftY

    ;; check top boundary
    local.get $topLeftY
    global.get $topPadding
    i32.le_u
    (if
      (then
        i32.const -1
        global.get $gameOverVelY
        i32.mul
        global.set $gameOverVelY
      )
    )

    ;; check right boundary
    local.get $offsetX
    local.get $width
    i32.add
    global.get $screenWidth
    i32.ge_u
    (if
      (then
        i32.const -1
        global.get $gameOverVelX
        i32.mul
        global.set $gameOverVelX
      )
    )

    ;; check bottom boundary
    local.get $topLeftY
    local.get $height
    i32.add
    global.get $screenHeight
    i32.ge_u
    (if
      (then
        i32.const -1
        global.get $gameOverVelY
        i32.mul
        global.set $gameOverVelY
      )
    )

    ;; check left boundary
    local.get $offsetX
    i32.const 0
    i32.le_u
    (if
      (then
        i32.const -1
        global.get $gameOverVelX
        i32.mul
        global.set $gameOverVelX
      )
    )

    ;; G
    i32.const 10
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; A
    i32.const 11
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; M
    i32.const 12
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; E
    i32.const 13
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 18
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; O
    i32.const 14
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; V
    i32.const 15
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; E
    i32.const 16
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
    i32.const 10
    local.get $offsetX
    i32.add
    local.set $offsetX
    ;; R
    i32.const 17
    local.get $offsetX
    local.get $topLeftY
    i32.const 100
    call $drawChar
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; game helpers
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $setDifficulty (param $difficulty i32)
    local.get $difficulty
    i32.const 1
    i32.eq
    (if
      (then
        i32.const 24
        global.set $scoreIncrement
      )
    )

    local.get $difficulty
    i32.const 2
    i32.eq
    (if
      (then
        i32.const 16
        global.set $scoreIncrement
      )
    )

    local.get $difficulty
    i32.const 3
    i32.eq
    (if
      (then
        i32.const 8
        global.set $scoreIncrement
      )
    )
  )

  (func $refreshGame
    i32.const 0
    global.set $snakePartsCounter

    i32.const 2
    i32.const 26
    i32.const 40
    call $addSnakeBlock

    i32.const 1
    i32.const 32
    i32.const 40
    call $addSnakeBlock

    i32.const 0
    i32.const 40
    i32.const 40
    call $addSnakeBlock

    call $placeFoodRandom

    i32.const 0
    global.set $score

    i32.const 0
    global.set $isGameOver

    i32.const 1
    global.set $snakeMoveState
  )

  (func $setSnakeMovementState (param $state i32)
    local.get $state
    global.set $snakeMoveState
  )

  (func $setCharDataAtIdx (param $idx i32) (param $color i32)
    local.get $idx
    i32.const 4
    i32.mul
    global.get $charsByteOffset
    i32.add
    local.get $color
    i32.store
  )

  (func $addSnakeBlock (param $idx i32) (param $x i32) (param $y i32)
    (local $blockByteOffset i32)
    local.get $idx
    i32.const 8
    i32.mul
    global.get $snakePartsByteOffset
    i32.add
    local.tee $blockByteOffset
    local.get $x
    i32.store ;; store x at idx

    local.get $blockByteOffset
    i32.const 4
    i32.add
    local.get $y
    i32.store ;; store y at idx + 1

    global.get $snakePartsCounter
    i32.const 1
    i32.add
    global.set $snakePartsCounter
  )

  (func $getSnakeHeadXY (result i32) (result i32)
    (local $outX i32)
    (local $outY i32)
    global.get $snakePartsByteOffset
    i32.load
    local.set $outX

    global.get $snakePartsByteOffset
    i32.const 4
    i32.add
    i32.load
    local.set $outY

    local.get $outX
    local.get $outY
  )

  (func $moveSnake
    (local $headX i32)
    (local $headY i32)
    (local $newHeadX i32)
    (local $newHeadY i32)
    (local $snakePartIdx i32)
    (local $partX i32)
    (local $partY i32)
    (local $partByteOffset i32)
    (local $hitBoundary i32)

    i32.const 0
    local.set $hitBoundary

    global.get $snakePartsByteOffset
    i32.load
    local.set $headX

    global.get $snakePartsByteOffset
    i32.const 4
    i32.add
    i32.load
    local.set $headY

    global.get $snakeMoveState
    i32.eqz ;; up
    (if
      (then
        local.get $headY
        i32.const 8
        i32.sub
        local.set $newHeadY

        local.get $headX
        local.set $newHeadX
      )
    )

    global.get $snakeMoveState
    i32.const 1
    i32.eq ;; right
    (if
      (then
        local.get $headX
        i32.const 8
        i32.add
        local.set $newHeadX

        local.get $headY
        local.set $newHeadY
      )
    )

    global.get $snakeMoveState
    i32.const 2
    i32.eq ;; bottom
    (if
      (then
        local.get $headY
        i32.const 8
        i32.add
        local.set $newHeadY

        local.get $headX
        local.set $newHeadX
      )
    )

    global.get $snakeMoveState
    i32.const 3
    i32.eq ;; left
    (if
      (then
        local.get $headX
        i32.const 8
        i32.sub
        local.set $newHeadX

        local.get $headY
        local.set $newHeadY
      )
    )
    
    ;; we have a new head XY for the snake
    ;; we then added the new head to the beginning of the snake
    ;; positions using unshift and remove the last element of the
    ;; snake using pop

    global.get $snakePartsCounter
    i32.const 1
    i32.sub
    local.set $snakePartIdx

    ;; global.get $snakePartsByteOffset
    (loop $shitSnakePartsLoop

      ;; fetch current snake part xy

      local.get $snakePartIdx
      i32.const 8
      i32.mul
      global.get $snakePartsByteOffset
      i32.add ;; last position byte offset
      local.tee $partByteOffset
      
      i32.load
      local.set $partX

      local.get $partByteOffset
      i32.const 4
      i32.add
      i32.load
      local.set $partY
      
      ;; shift snake part xy to next slot
      local.get $partByteOffset
      i32.const 8
      i32.add
      local.get $partX
      i32.store

      local.get $partByteOffset
      i32.const 12
      i32.add
      local.get $partY
      i32.store

      local.get $snakePartIdx
      i32.const 1
      i32.sub
      local.tee $snakePartIdx
      i32.const -1
      i32.ne
      (br_if $shitSnakePartsLoop)
    )

    ;; check if food has been eaten

    global.get $foodX
    local.get $headX
    i32.eq
    (if
      (then
        global.get $foodY
        local.get $headY
        i32.eq
        (if
          (then
            ;; food has been eaten!
            ;; 1. generate new food position
            ;; 2. increase score
            ;; 3. increase snake length

            call $placeFoodRandom

            global.get $snakePartsCounter
            i32.const 1
            i32.add
            global.set $snakePartsCounter

            global.get $score
            global.get $scoreIncrement
            i32.add
            global.set $score
          )
        )
      )
    )

    ;; check if snake intersects itself
    i32.const 1
    local.set $snakePartIdx
    (loop $checkIfSnakeIntersectsLoop

      i32.const 8
      local.get $snakePartIdx
      i32.mul
      global.get $snakePartsByteOffset
      i32.add
      i32.const 8
      i32.add
      local.tee $partByteOffset
      i32.load
      local.set $partX

      local.get $partByteOffset
      i32.const 4
      i32.add
      i32.load
      local.tee $partY

      local.get $newHeadY
      i32.eq
      (if
        (then
          local.get $partX
          local.get $newHeadX
          i32.eq
          (if
            (then
              i32.const 1
              global.set $isGameOver  
              i32.const 1
              local.set $hitBoundary
              call $onGameOver
            )
          )
        )
      )

      local.get $snakePartIdx
      i32.const 1
      i32.add
      local.tee $snakePartIdx
      global.get $snakePartsCounter
      i32.ne
      (br_if $checkIfSnakeIntersectsLoop)
    )

    ;; snakePartIdxif wall has been hit

    ;; right wall
    global.get $screenWidth
    local.get $newHeadX
    
    i32.le_u
    (if
      (then
        i32.const 1
        global.set $isGameOver  
        i32.const 1
        local.set $hitBoundary
        call $onGameOver
      )
    )

    ;; left boundary
    local.get $newHeadX
    i32.const -8
    i32.le_s
    (if
      (then
        i32.const 1
        global.set $isGameOver
        i32.const 1
        local.set $hitBoundary
        call $onGameOver
      )
    )

    ;; top boundary
    local.get $newHeadY
    global.get $topPadding
    i32.const 8
    i32.sub
    i32.le_s
    (if
      (then
        i32.const 1
        global.set $isGameOver
        i32.const 1
        local.set $hitBoundary
        call $onGameOver
      )
    )

    ;; bottom boundary
    global.get $screenHeight
    local.get $newHeadY
    i32.le_s
    (if
      (then
        i32.const 1
        global.set $isGameOver
        i32.const 1
        local.set $hitBoundary
        call $onGameOver
      )
    )

    local.get $hitBoundary
    i32.eqz
    (if
      (then
        global.get $snakePartsByteOffset
        local.get $newHeadX
        i32.store

        global.get $snakePartsByteOffset
        i32.const 4
        i32.add
        local.get $newHeadY
        i32.store
      )
    )

  )

  (func $getRandomXYInGrid (result i32) (result i32)
    (local $outX i32)

    global.get $screenWidth
    call $random_int
    i32.const 8
    i32.div_u
    i32.const 8
    i32.mul
    local.set $outX

    global.get $gameGridHeight
    call $random_int
    i32.const 8
    i32.div_u
    i32.const 8
    i32.mul
    global.get $topPadding
    i32.add
    local.get $outX
  )

  (func $placeFoodRandom
    (local $foodRandomX i32)
    (local $foodRandomY i32)
    (local $snakePartIdx i32)
    (local $snakePartByteOffset i32)
    (local $newFoodPositionLiesOnSnake i32)

    call $getRandomXYInGrid
    local.set $foodRandomX
    local.set $foodRandomY

    global.get $snakePartsByteOffset
    local.set $snakePartByteOffset

    i32.const 0
    local.set $snakePartIdx

    (loop $checkIfFoodPositionLiesOnSnakeLoop

      i32.const 8
      local.get $snakePartIdx
      i32.mul
      local.get $snakePartByteOffset
      i32.add
      local.tee $snakePartByteOffset
      i32.load ;; snake part x
      local.get $foodRandomX
      i32.eq
      (if
        (then
          local.get $snakePartByteOffset
          i32.const 4
          i32.add
          i32.load ;; snake part y
          local.get $foodRandomY
          i32.eq
          (if
            (then
              call $placeFoodRandom
              return
            )
          )
        )
      )

      i32.const 1
      local.get $snakePartIdx
      i32.add
      local.tee $snakePartIdx
      global.get $snakePartsCounter
      i32.eq
      (br_if $checkIfFoodPositionLiesOnSnakeLoop)
    )

    local.get $foodRandomX
    global.set $foodX
    local.get $foodRandomY
    global.set $foodY
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Program start / update loop
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $updateFrame

    call $clearBackground
    call $drawDebugGrid
    call $drawBorder
    call $drawScore
    call $drawSnake

    global.get $isGameOver
    (if
      (then
        call $drawGameOver  
      )
      (else
        call $moveSnake
        call $drawFood
      )
    )

    global.get $frameCounter
    i32.const 1
    i32.add
    global.set $frameCounter
  )
  (func $main
    call $refreshGame
  )
  
)
