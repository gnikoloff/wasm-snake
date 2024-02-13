(module
  (memory 3)
  (export "memory" (memory 0))

  (global $screenSizeBytes (mut i32) (i32.const 0))

  (func $putColor (param $x i32) (param $y i32) (param $color i32)
    ;; local.get $idx
    ;; i32.const 4
    ;; i32.mul
    ;; local.get $color
    ;; i32.store
  )

  (func $drawSnakeBlock (param $x i32) (param $y i32) (param $size i32)
    (local $xStart i32)
    (local $yStart i32)
    (local $xEnd i32)
    (local $yEnd i32)
    (local $halfSize i32)

    local.get $size
    i32.const 2
    i32.div_u
    local.set $halfSize

    ;; calc xStart
    local.get $x
    local.get $halfSize
    i32.sub
    local.set $xStart

    ;; calc yStart
    local.get $y
    local.get $halfSize
    i32.sub
    local.set $yStart

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
      local.get $xStart
      i32.const 1
      i32.add
      local.set $x
      local.get $x
      local.get $xEnd
      i32.lt_u
      (br_if $xLoop)
    )
  )

  (func $main
    (local $var i32)
    (local $snakeX i32)
    (local $snakeY i32)
    (local $x i32)
    (local $y i32)
    (local $isSnakeX i32)
    (local $isSnakeY i32)

    i32.const 32768
    global.set $screenSizeBytes

    global.get $screenSizeBytes
    i32.const 4
    i32.add
    i32.const 100
    i32.store 

    global.get $screenSizeBytes
    i32.const 8
    i32.add
    i32.const 100
    i32.store
    
    (local.set $var (global.get $screenSizeBytes))

    global.get $screenSizeBytes
    i32.const 4
    i32.add
    i32.load
    local.set $snakeX

    global.get $screenSizeBytes
    i32.const 8
    i32.add
    i32.load
    local.set $snakeY

    (loop $my_loop
      
      local.get $var
      i32.const 256
      i32.rem_u
      local.set $x

      local.get $var
      i32.const 256
      i32.div_u
      local.set $y

      local.get $x
      local.get $snakeX
      i32.eq
      local.set $isSnakeX

      local.get $y
      local.get $snakeY
      i32.eq
      local.set $isSnakeY

      local.get $isSnakeX
      local.get $isSnakeY
      i32.and
      (if
        (then
          local.get $var
          i32.const 200
          call $putColor
        )
        (else
          local.get $var
          i32.const 100
          call $putColor
        )
      )

      local.get $var
      i32.const 1
      i32.sub
      local.set $var

      local.get $var

      i32.const -1
      i32.ne
      (br_if $my_loop)
    )
  )
  (start $main)
)
