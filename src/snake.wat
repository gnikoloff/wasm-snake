(module
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;;
  ;; Classic Snake in WebAssembly text format
  ;;
  ;; Memory layout:
  ;;
  ;; One virtual page in WASM is 64kb. We will need 3 pages to hold all of the data (pixel buffer + game state).
  ;; 64kb * 3 pages = 192kb =
  ;; 
  ;; 196608 bytes for the entire program
  ;;  _______________________________________________________________________________________________________
  ;; | Offset:                           |                             |                                     |
  ;; | index 0                           | index 35000                 | index 35100                         |
  ;; | byte index 0                      | byte index 140000           | byte index 140400                   |
  ;; |-----------------------------------|-----------------------------|-------------------------------------|
  ;; | VRAM (pixel buffer contents)      | Snake part positions (XY)   | Char encodings (256 bytes per char) |
  ;; | 256 * 128 = 32768 pixels          | Max parts allowed = 100     | Chars: 0123456789                   |
  ;; | 4 bytes per pixel = 131072 bytes  | 2 bytes for XY = 400 bytes  | 256 * 10 bytes = 2560 bytes         |
  ;; |___________________________________|_____________________________|_____________________________________|
  ;; 
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (memory 3)

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; global vars
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (global $screenWidth i32 (i32.const 256))
  (global $screenHeight i32 (i32.const 128))
  (global $vramSizeBytes i32 (i32.const 32768))        ;; screenWidth * screenHeight

  (global $topPadding i32 (i32.const 10))
  (global $bottomPadding i32 (i32.const 20))
  (global $rightPadding i32 (i32.const 4))
  (global $leftPadding i32 (i32.const 4))
  
  (global $snakeBlockSize i32 (i32.const 10))
  (global $snakeXYsByteOffset i32 (i32.const 140000))
  (global $snakePartCount (mut i32) (i32.const 0))
  (global $snakeMaxPartsCount i32 (i32.const 100))
  (global $snakeMoveState (mut i32) (i32.const 0))     ;; 0 - top ;; 1 - right ;; 2 - bottom ;; 3 - left ;;

  (global $charsByteOffset i32 (i32.const 140200))
  (global $charWidth i32 (i32.const 8))
  (global $charPixelSize i32 (i32.const 64))
  (global $charByteSize i32 (i32.const 256))

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
    (local.set $i (global.get $vramSizeBytes))
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

  (func $drawSnakeBlock (param $centerX i32) (param $centerY i32) (param $size i32)
    (local $x i32)
    (local $y i32)
    (local $xStart i32)
    (local $yStart i32)
    (local $xEnd i32)
    (local $yEnd i32)
    (local $halfSize i32)

    ;; calc half size
    local.get $size
    i32.const 2
    i32.div_u
    local.set $halfSize

    ;; calc x
    local.get $centerX
    local.get $halfSize
    i32.sub
    local.tee $xStart
    local.set $x

    ;; calc y
    local.get $centerY
    local.get $halfSize
    i32.sub
    local.tee $yStart
    local.set $y

    ;; calc xEnd
    local.get $x
    local.get $halfSize
    i32.add
    local.set $xEnd

    ;; calc yEnd
    local.get $y
    local.get $halfSize
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
      global.get $charsByteOffset
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

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; game helpers
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $setSnakeMovementState (param $state i32)
    local.get $state
    global.set $snakeMoveState
  )

  (func $allocateSnakeBlock (param $x i32) (param $y i32)
    (local $blockOffsetBytes i32)
    global.get $snakePartCount
    i32.const 8 ;; 2 for XY * 4 bytes per i32
    i32.mul
    global.get $snakeXYsByteOffset
    i32.add
    local.tee $blockOffsetBytes

    local.get $x
    i32.store ;; store X

    local.get $blockOffsetBytes
    i32.const 4
    i32.add
    local.get $y
    i32.store ;; store y
    
    ;; increment snakePartCount
    global.get $snakePartCount
    i32.const 1
    i32.add
    global.set $snakePartCount
  )

  (func $getSnakeBlockPosXY (param $blockIdx i32) (result i32) (result i32)
    (local $xByteOffset i32)
    (local $yByteOffset i32)
    local.get $blockIdx
    i32.const 8 ;; (XY) * 4 bytes per i32
    i32.mul
    global.get $snakeXYsByteOffset
    i32.add
    local.tee $xByteOffset

    i32.const 4
    i32.add
    local.set $yByteOffset

    local.get $xByteOffset
    i32.load
    local.get $yByteOffset
    i32.load
  )

  (func $setSnakeBlockPosXY (param $blockIdx i32) (param $x i32) (param $y i32)
    (local $xByteOffset i32)
    (local $yByteOffset i32)
    local.get $blockIdx
    i32.const 8 ;; (XY) * 4 bytes per i32
    i32.mul
    global.get $snakeXYsByteOffset
    i32.add
    local.tee $xByteOffset

    i32.const 4
    i32.add
    local.tee $yByteOffset
    local.get $y
    i32.store ;; set y

    local.get $xByteOffset
    local.get $x
    i32.store ;; set x
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

    ;; draw top border
    (loop $bottomBorderLoop
      local.get $x
      global.get $screenHeight
      global.get $bottomPadding
      i32.sub
      i32.const 255
      call $putPixelAtXY

      local.get $x
      i32.const 1
      i32.add
      local.tee $x
      local.get $xEnd
      i32.ne
      (br_if $bottomBorderLoop)
    )

    global.get $screenHeight
    global.get $bottomPadding
    i32.sub
    local.set $yEnd

    global.get $topPadding
    local.tee $y
    local.set $yStart

    ;; draw left border
    (loop $leftBorderLoop
      global.get $leftPadding
      local.get $y
      i32.const 255
      call $putPixelAtXY

      local.get $y
      i32.const 1
      i32.add
      local.tee $y
      local.get $yEnd
      i32.ne
      (br_if $leftBorderLoop)
    )
    local.get $yStart
    local.set $y

    ;; draw right border
    (loop $rightBorderLoop
      global.get $screenWidth
      global.get $rightPadding
      i32.sub
      local.get $y
      i32.const 255
      call $putPixelAtXY

      local.get $y
      i32.const 1
      i32.add
      local.tee $y
      local.get $yEnd
      i32.ne
      (br_if $rightBorderLoop)
    )
  )

  (func $drawSnake
    (local $partIdx i32)
    (local $snakeX i32)
    (local $snakeY i32)

    i32.const 0
    local.set $partIdx
    
    (loop $drawSnakeLoop
      local.get $partIdx
      i32.const 8
      i32.mul
      global.get $snakeXYsByteOffset
      i32.add
      i32.load
      local.set $snakeX

      local.get $partIdx
      i32.const 8
      i32.mul
      global.get $snakeXYsByteOffset
      i32.add
      i32.const 4
      i32.add
      i32.load
      local.set $snakeY

      local.get $snakeX
      local.get $snakeY
      global.get $snakeBlockSize
      call $drawSnakeBlock

      local.get $partIdx
      i32.const 1
      i32.add
      local.tee $partIdx
      global.get $snakePartCount
      i32.ne
      (br_if $drawSnakeLoop)
    )
  )

  (func $moveSnakeHead
    (local $x i32)
    (local $y i32)
    (local $isPositiveX i32)
    (local $isNegativeX i32)
    (local $isPositiveY i32)
    (local $isNegativeY i32)

    ;; get correct x and y positions for the head (idx 0)
    i32.const 0
    call $getSnakeBlockPosXY
    local.set $y
    local.set $x

    ;; determine right movement based on $snakeMoveState
    global.get $snakeMoveState
    i32.const 1
    i32.eq
    local.set $isPositiveX

    global.get $snakeMoveState
    i32.const 3
    i32.eq

    ;; handle horizontal movement
    local.tee $isNegativeX    
    local.get $isPositiveX
    i32.or
    (if
      (then
        local.get $isPositiveX
        i32.const 1
        i32.and
        (if
          (then       
            local.get $x
            i32.const 6
            i32.add
            local.set $x
          )
          (else
            local.get $x
            i32.const 6
            i32.sub
            local.set $x
          )
        )
        ;; test right border
        local.get $x
        i32.const 5
        i32.add
        global.get $screenWidth
        i32.ge_u
        (if
          ;; wrap around to left border
          (then
            i32.const 5
            local.set $x
          )
        )

        ;; test left border
        local.get $x
        i32.const 5
        i32.sub
        i32.const 0
        i32.le_u
        (if
          ;; wrap around to right border
          (then
            global.get $screenWidth
            i32.const 5
            i32.sub
            local.set $x
          )
        )
      ) 
    )

    ;; handle vertical movement
    global.get $snakeMoveState
    i32.const 2
    i32.eq
    local.set $isPositiveY

    global.get $snakeMoveState
    i32.eqz
    local.tee $isNegativeY

    local.get $isPositiveY
    i32.or
    (if
      (then
        local.get $isPositiveY
        i32.const 1
        i32.and
        (if
          (then
            local.get $y
            i32.const 6
            i32.add
            local.set $y
          )
          (else
            local.get $y
            i32.const 6
            i32.sub
            local.set $y
          )
        )

        ;; test bottom border
        local.get $y
        i32.const 5
        i32.add
        global.get $screenHeight
        i32.ge_u
        (if
          ;; wrap around to left border
          (then
            i32.const 5
            local.set $y
          )
        )

        ;; test top border
        local.get $y
        i32.const 5
        i32.sub
        i32.const 0
        i32.le_u
        (if
          ;; wrap around to right border
          (then
            global.get $screenHeight
            i32.const 5
            i32.sub
            local.set $y
          )
        )
      )
    )

    i32.const 0
    local.get $x
    local.get $y
    call $setSnakeBlockPosXY
  )

  (func $moveSnake
    (local $partIdx i32)
    (local $prevBlockX i32)
    (local $prevBlockY i32)

    call $moveSnakeHead

    i32.const 1
    local.set $partIdx
    (loop $moveSnakeBodyLoop

      local.get $partIdx
      i32.const 1
      i32.sub
      call $getSnakeBlockPosXY
      local.set $prevBlockY
      local.set $prevBlockX

      local.get $partIdx
      local.get $prevBlockX
      local.get $prevBlockY
      call $setSnakeBlockPosXY

      local.get $partIdx
      i32.const 1
      i32.add
      local.tee $partIdx
      global.get $snakePartCount
      i32.ne
      br_if $moveSnakeBodyLoop
    )
  )

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; Program start / update loop
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (func $updateFrame
    ;; call $moveSnake

    call $clearBackground
    call $drawBorder
    call $drawSnake

    i32.const 0
    i32.const 20
    i32.const 20
    call $drawChar
  )

  (func $main
    ;; init 4 snake blocks laid out horizontally on app startup
    i32.const 112
    i32.const 100
    call $allocateSnakeBlock

    i32.const 118
    i32.const 100
    call $allocateSnakeBlock

    i32.const 124
    i32.const 100
    call $allocateSnakeBlock
    i32.const 130
    i32.const 100
    call $allocateSnakeBlock
  )
  (start $main)
)
