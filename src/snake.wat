(module
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; Classic Snake in WebAssembly text format
  ;;
  ;; Memory layout:
  ;;
  ;; One virtual page in WASM is 64kb. We will need 3 pages to hold all of the data (pixel buffer + game state).
  ;; 64kb * 3 pages = 192kb = 196608 bytes for the entire program
  ;;  _____________________________________________________________________________________________________________________________________
  ;; | Offset:                                   |                                      |                                                 |
  ;; | index 0                                   | index 37500                          | index 40000                                     |
  ;; | byte index 0                              | byte index 150000                    | byte index 160000                               |
  ;; |-------------------------------------------|--------------------------------------|-------------------------------------------------|
  ;; | VRAM (pixel buffer contents)              | Char encodings (64 pixels per char)  | Snake parts positions (max 300)                 |
  ;; | 256px width * 144 pxheight = 36864 pixels | Chars: 0123456789                    | Each position has 2 coords (XY)                 |
  ;; | 4 bytes per pixel = 147456 bytes          | 64 * 10 chars * 4 bytes = 2560 bytes | 300 positions * 2 coords * 4 bytes = 2400 bytes |
  ;; |___________________________________________|______________________________________|_________________________________________________|
  ;; 
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (memory 3)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; global vars
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (global $screenWidth i32 (i32.const 256))
  (global $screenHeight i32 (i32.const 144))
  (global $vramPixelCount i32 (i32.const 36864))        ;; screenWidth * screenHeight

  (global $topPadding i32 (i32.const 16))
  (global $bottomPadding i32 (i32.const 4))
  (global $rightPadding i32 (i32.const 4))
  (global $leftPadding i32 (i32.const 4))
  
  (global $snakeMoveState (mut i32) (i32.const 0))     ;; 0 - top ;; 1 - right ;; 2 - bottom ;; 3 - left ;;
  (global $snakePositionCounter (mut i32) (i32.const 0))
  (global $snakePositionsByteOffset i32 (i32.const 160000))

  (global $charsByteOffset i32 (i32.const 150000))
  (global $charWidth i32 (i32.const 8))
  (global $charPixelSize i32 (i32.const 64))
  (global $charByteSize i32 (i32.const 256))

  (global $score (mut i32) (i32.const 0))
  (global $frameCounter (mut i32) (i32.const 0))
  (global $foodColorState (mut i32) (i32.const 0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; exports (visible from JS)
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (export "memory" (memory 0))
  (export "updateFrame" (func $updateFrame))
  (export "setSnakeMovementState" (func $setSnakeMovementState))
  (export "setCharDataAtIdx" (func $setCharDataAtIdx))

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
    local.set $xStart

    local.get $y
    local.set $yStart

    ;; calc xEnd
    local.get $x
    i32.const 8
    i32.add
    local.set $xEnd

    ;; calc yEnd
    local.get $y
    i32.const 8
    i32.add
    local.set $yEnd

    (loop $xLoop
      local.get $x
      i32.const 1
      i32.add
      local.set $x

      (loop $yLoop
        local.get $y
        i32.const 1
        i32.add
        local.set $y

        ;; draw pixel within block
        local.get $x
        local.get $y
        i32.const 255
        call $putPixelAtXY

        local.get $y
        local.get $yEnd
        i32.lt_u
        (br_if $yLoop)
      )
      ;; reset y to equal yStart
      local.get $yStart
      local.set $y

      local.get $x
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

        global.get $snakeMoveState
        i32.eqz ;; up
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
          )
        )

        global.get $snakeMoveState
        i32.const 1
        i32.eq ;; right
        (if
          (then
            local.get $xStart
            i32.const 6
            i32.add
            local.set $eyeX

            local.get $yStart
            i32.const 3
            i32.add
            local.set $eyeY
          )
        )

        global.get $snakeMoveState
        i32.const 2
        i32.eq ;; bottom
        (if
          (then
            local.get $xStart
            i32.const 3
            i32.add
            local.set $eyeX

            local.get $yStart
            i32.const 6
            i32.add
            local.set $eyeY
          )
        )

        global.get $snakeMoveState
        i32.const 3
        i32.eq ;; left
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
          )
        )

        

        local.get $eyeX
        local.get $eyeY
        i32.const 0
        call $putPixelAtXY
      )
    )
  )

  (func $drawChar (param $charIdx i32) (param $offsetX i32) (param $offsetY i32)
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
          local.get $charByte
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
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit1
    local.get $xOffset
    i32.const 3
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit2
    local.get $xOffset
    i32.const 3
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit3
    local.get $xOffset
    i32.const 3
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit4
    local.get $xOffset
    i32.const 3
    call $drawChar

    local.get $xOffset
    i32.const 10
    i32.add
    local.set $xOffset

    local.get $digit5
    local.get $xOffset
    i32.const 3
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
        i32.const 50
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
        i32.const 50
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

  (func $drawFood (param $x i32) (param $y i32)
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
      global.get $snakePositionsByteOffset
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
      global.get $snakePositionCounter
      i32.ne
      (br_if $drawSnakeBlocksLoop)
    )
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; game helpers
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
    global.get $snakePositionsByteOffset
    i32.add
    local.tee $blockByteOffset
    local.get $x
    i32.store ;; store x at idx

    local.get $blockByteOffset
    i32.const 4
    i32.add
    local.get $y
    i32.store ;; store y at idx + 1

    global.get $snakePositionCounter
    i32.const 1
    i32.add
    global.set $snakePositionCounter
  )

  (func $getSnakeHeadXY (result i32) (result i32)
    (local $outX i32)
    (local $outY i32)
    global.get $snakePositionsByteOffset
    i32.load
    local.set $outX

    global.get $snakePositionsByteOffset
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
    (local $partX i32)
    (local $partY i32)
    (local $shiftIdx i32)
    (local $shiftByteOffset i32)
    (local $nextShiftIdx i32)
    (local $nextShiftByteOffset i32)

    global.get $snakePositionsByteOffset
    i32.load
    local.set $headX

    global.get $snakePositionsByteOffset
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
    global.get $snakePositionCounter
    local.tee $nextShiftIdx
    i32.const 1
    i32.sub
    local.set $shiftIdx
    

    (loop $shiftSnakePositionsLoop

      local.get $shiftIdx
      i32.const 8
      i32.mul
      global.get $snakePositionsByteOffset
      i32.add
      i32.const 8
      i32.add
      local.set $nextShiftByteOffset

      local.get $shiftIdx
      i32.const 8
      i32.mul
      global.get $snakePositionsByteOffset
      i32.add
      local.tee $shiftByteOffset
      i32.load
      local.set $partX

      local.get $shiftByteOffset
      i32.const 4
      i32.add
      i32.load
      local.set $partY

      local.get $nextShiftByteOffset
      local.get $partX
      i32.store

      local.get $nextShiftByteOffset
      i32.const 4
      i32.add
      local.get $partY
      i32.store

      local.get $shiftIdx
      local.tee $nextShiftIdx
      i32.const 1
      i32.sub
      local.tee $shiftIdx


      i32.const -1
      i32.ne
      (br_if $shiftSnakePositionsLoop)
    )

    local.get $nextShiftByteOffset
    i32.const 8
    i32.sub
    local.get $newHeadX
    i32.store

    local.get $nextShiftByteOffset
    i32.const 4
    i32.sub
    local.get $newHeadY
    i32.store

    
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Program start / update loop
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $updateFrame
    call $moveSnake

    call $clearBackground
    ;; call $drawDebugGrid
    call $drawBorder
    call $drawScore
    call $drawSnake

    i32.const 80
    i32.const 80
    call $drawFood

    global.get $score
    i32.const 1
    i32.add
    global.set $score

    global.get $frameCounter
    i32.const 1
    i32.add
    global.set $frameCounter

    i32.const 1
    call $getSnakeHeadXY
    call $addSnakeBlock
  )
  (func $main
    ;; i32.const 2
    ;; i32.const 24
    ;; i32.const 40
    ;; call $addSnakeBlock

    ;; i32.const 1
    ;; i32.const 32
    ;; i32.const 40
    ;; call $addSnakeBlock

    i32.const 0
    i32.const 40
    i32.const 40
    call $addSnakeBlock
  )
  (start $main)
)
