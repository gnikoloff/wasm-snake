# Classic Snake in WebAssembly

![Snake preview](https://github.com/gnikoloff/wasm-snake/blob/main/preview.png?raw=true)

Snake written in WebAssembly Text (WAT) format and compiled to WASM bytecode.

All graphics, game state and logic are written in WAT.
Module is loaded in JS (host environment) which is responsible for game tick, user input and random number generator seeding.

The WASM memory consists of 3 virtual pages (64kb each) = 192kb total. Within those exist the pixel buffer, the snake and food positions and the character data. The memory is shared with JS, which then blits it to the screen using WebGL2.

You can refer to [src/snake.wat](https://github.com/gnikoloff/wasm-snake/blob/main/src/snake.wat) for detailed memory break down and lots of comments.

### References and readings

- [Computer Systems: A Programmer's Perspective](https://www.amazon.com/Computer-Systems-Programmers-Perspective-3rd/dp/013409266X)
- [Understanding WebAssembly text format](https://developer.mozilla.org/en-US/docs/WebAssembly/Understanding_the_text_format)
- [JavaScript snake game tutorial: Build a simple, interactive game](https://www.educative.io/blog/javascript-snake-game-tutorial)
