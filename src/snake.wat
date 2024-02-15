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
  ;;  __________________________________________________________________________________________
  ;; | Offset:                           |                             |                       |
  ;; | 0 bytes                           | 140000 bytes                | 14200 bytes           |
  ;; |-----------------------------------|-----------------------------|-----------------------|
  ;; | VRAM (pixel buffer contents)      | Snake part positions (XY)   | Snake parts counter   |
  ;; | 256 * 128 = 32768 pixels          | Max parts allowed = 100     | 4 byte i32            |
  ;; | 4 bytes per pixel = 131072 bytes  | 2 bytes for XY = 200 bytes  |                       |
  ;; |___________________________________|_____________________________|_______________________|
  ;; 
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  ;; preallocate 3 pages of VM
  ;; one page is 64kb
  ;; so total memory = 192kb
  (memory 3)
  ;; make the memory visible to JS
  (export "memory" (memory 0))

  ;; global vars
  (global $screenWidth i32 (i32.const 256))
  (global $screenHeight i32 (i32.const 128))
  (global $vramSizeBytes i32 (i32.const 32768))        ;; screenWidth * screenHeight
  (global $snakeXYsByteOffset i32 (i32.const 140000))
  (global $snakePartCount (mut i32) (i32.const 0))
  (global $snakeMaxPartsCount i32 (i32.const 100))

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

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; game helpers
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

  (func $allocateSnakeBlock (param $x i32) (param $y i32)
    (local $blockOffsetBytes i32)
    global.get $snakePartCount
    i32.const 2 ;; 2 for XY
    i32.mul
    i32.const 4 ;; 4 bytes per i32
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
      i32.const 10
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

  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; main
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  (export "updateFrame" (func $updateFrame))
  (func $updateFrame
    call $clearBackground
    call $drawSnake
  )

  (func $main
    i32.const 112
    i32.const 100
    call $allocateSnakeBlock

    i32.const 118
    i32.const 100
    call $allocateSnakeBlock

    i32.const 124
    i32.const 100
    call $allocateSnakeBlock

    i32.const 124
    i32.const 106
    call $allocateSnakeBlock
  )
  (start $main)
)
