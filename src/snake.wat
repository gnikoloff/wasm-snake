(module
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; Classic Snake in WebAssembly text format
  ;;
  ;; Memory layout:
  ;;
  ;; One virtual page in WASM is 64kb. We will need 3 pages to hold all of the data (pixel buffer + game state).
  ;; 64kb * 3 pages = 192kb = 196608 bytes for the entire program
  ;;  ___________________________________________________________________________
  ;; | Offset:                           |                                      |
  ;; | index 0                           | index 37500                          |
  ;; | byte index 0                      | byte index 150000                    |
  ;; |-----------------------------------|--------------------------------------|
  ;; | VRAM (pixel buffer contents)      | Char encodings (64 pixels per char)  |
  ;; | 256 * 144 = 36864 pixels          | Chars: 0123456789                    |
  ;; | 4 bytes per pixel = 147456 bytes  | 64 * 10 chars * 4 bytes = 2560 bytes |
  ;; |___________________________________|______________________________________|
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

  (global $charsByteOffset i32 (i32.const 150000))
  (global $charWidth i32 (i32.const 8))
  (global $charPixelSize i32 (i32.const 64))
  (global $charByteSize i32 (i32.const 256))

  (global $score (mut i32) (i32.const 0))

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; exports (visible from JS)
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (export "memory" (memory 0))
  (export "updateFrame" (func $updateFrame))
  (export "setSnakeMovementState" (func $setSnakeMovementState))

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
        local.get $xStart
        i32.const 3
        i32.add
        local.set $eyeX

        local.get $yStart
        i32.const 4
        i32.add
        local.set $eyeY

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

      local.get $charPixelWorldX
      local.get $charPixelWorldY
      local.get $charByte
      call $putPixelAtXY

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
    
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; game helpers
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $setSnakeMovementState (param $state i32)
    local.get $state
    global.set $snakeMoveState
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Program start / update loop
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $updateFrame
    ;; call $moveSnake

    call $clearBackground
    call $drawDebugGrid
    call $drawBorder
    call $drawScore

    i32.const 112
    i32.const 112
    i32.const 1
    call $drawSnakeBlock

    global.get $score
    i32.const 1
    i32.add
    global.set $score
  )

  (func $main
    
  )
  (start $main)
)
