# Classic Snake in WebAssembly

![Snake preview](https://github.com/gnikoloff/wasm-snake/blob/main/preview.png?raw=true)

Snake written in WebAssembly Text (WAT) format and compiled to WASM bytecode.

All of the game graphics, state and logic are written in WebAssembly Text. The host environment (Javascript) is responsible for:

1. Game tick loop
2. User input
3. Providing characters "0123456789GAMEOVER" byte data on game startup
4. Blitting the pixel buffer to the display with WebGL2

The game uses 3 virtual pages of memory (64kb each) for a total of 192kb. Within those exist the pixel buffer contents, the characters data and snake positions. For more detailed breakdown you can check [src/snake.wat](https://github.com/gnikoloff/wasm-snake/blob/main/src/snake.wat).

The memory is shared between WASM and JS. On each game tick, the pixel buffer region of the memory is transferred to a WebGL2 texture, uploaded to the GPU and blitted to the screen.

### References and readings

- [Computer Systems: A Programmer's Perspective](https://www.amazon.com/Computer-Systems-Programmers-Perspective-3rd/dp/013409266X)
- [Understanding WebAssembly text format](https://developer.mozilla.org/en-US/docs/WebAssembly/Understanding_the_text_format)
- [JavaScript snake game tutorial: Build a simple, interactive game](https://www.educative.io/blog/javascript-snake-game-tutorial)
