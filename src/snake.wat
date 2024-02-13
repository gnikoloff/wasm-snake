(module
  ;; preallocate 3 pages of VM
  ;; one page is 64kb
  ;; so total memory = 192kb
  (memory 3)
  (export "memory" (memory 0))

  (global $screenWidth (mut i32) (i32.const 0))
  (global $screenHeight (mut i32) (i32.const 0))
  (global $vramSizeBytes (mut i32) (i32.const 0))

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
      local.set $i

      local.get $i
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
    local.set $xStart
    local.get $xStart
    local.set $x

    ;; calc y
    local.get $centerY
    local.get $halfSize
    i32.sub
    local.set $yStart
    local.get $yStart
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

  (func $main
    
    (local $snakeX i32)
    (local $snakeY i32)
    (local $x i32)
    (local $y i32)
    (local $isSnakeX i32)
    (local $isSnakeY i32)

    ;; Initialize global vars
    i32.const 256
    global.set $screenWidth

    i32.const 128
    global.set $screenHeight

    global.get $screenWidth
    global.get $screenHeight
    i32.mul
    global.set $vramSizeBytes

    global.get $vramSizeBytes
    i32.const 4
    i32.add
    i32.const 200
    i32.store 

    global.get $vramSizeBytes
    i32.const 8
    i32.add
    i32.const 100
    i32.store
    
    global.get $vramSizeBytes
    i32.const 4
    i32.add
    i32.load
    local.set $snakeX

    global.get $vramSizeBytes
    i32.const 8
    i32.add
    i32.load
    local.set $snakeY

    call $clearBackground
    
    i32.const 100
    i32.const 100
    i32.const 10
    call $drawSnakeBlock

    i32.const 106
    i32.const 100
    i32.const 10
    call $drawSnakeBlock
    i32.const 112
    i32.const 100
    i32.const 10
    call $drawSnakeBlock

    ;; (loop $my_loop
      
    ;;   local.get $var
    ;;   i32.const 256
    ;;   i32.rem_u
    ;;   local.set $x

    ;;   local.get $var
    ;;   i32.const 256
    ;;   i32.div_u
    ;;   local.set $y

    ;;   local.get $x
    ;;   local.get $snakeX
    ;;   i32.eq
    ;;   local.set $isSnakeX

    ;;   local.get $y
    ;;   local.get $snakeY
    ;;   i32.eq
    ;;   local.set $isSnakeY

    ;;   local.get $isSnakeX
    ;;   local.get $isSnakeY
    ;;   i32.and
    ;;   (if
    ;;     (then
    ;;       local.get $x
    ;;       local.get $y
    ;;       i32.const 200
    ;;       call $putPixelAtXY
    ;;     )
    ;;     (else
    ;;       local.get $x
    ;;       local.get $y
    ;;       i32.const 30
    ;;       call $putPixelAtXY
    ;;     )
    ;;   )

    ;;   local.get $var
    ;;   i32.const 1
    ;;   i32.sub
    ;;   local.set $var

      
    ;; )
  )
  (start $main)
)
