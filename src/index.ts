import snakeWasmURL from "./snake.wasm?url";
import { createPlane, createProgram } from "./lib/hwoa-rang-gl2";
import { CHAR_DATA } from "./constants";

interface IWebAssemblyExport {
	memory: {
		buffer: Int32Array;
	};
	updateFrame: () => void;
	setSnakeMovementState: (state: SnakeMoveState) => void;
	setCharDataAtIdx: (idx: number, color: number) => void;
}

type SnakeMoveState = 0 | 1 | 2 | 3; // 0 - Up // 1 - Right // 2 - Bottom // 3 - Left

const CANVAS_WIDTH = 256;
const CANVAS_HEIGHT = 144;
const FPS = 4;

let snakeState: SnakeMoveState = 1;
let canChangeSnakeState = true;

// Init canvas
const $glContiner = document.getElementById("gl-container")!;
const $c = document.createElement("canvas") as HTMLCanvasElement;
const gl = $c.getContext("webgl2")!;
$c.width = CANVAS_WIDTH;
$c.height = CANVAS_HEIGHT;
$c.setAttribute("id", "c");
$glContiner.appendChild($c);

////////////////////////////////////////////////////////////////////////
// Instantiate WASM module
////////////////////////////////////////////////////////////////////////
const { module, instance } = await WebAssembly.instantiateStreaming(
	fetch(snakeWasmURL),
	{},
);
const exports = instance.exports as unknown as IWebAssemblyExport;
const memoryAsInt32 = new Int32Array(exports.memory.buffer);

for (let i = 0; i < CHAR_DATA.length; i++) {
	for (let n = 0; n < 64; n++) {
		exports.setCharDataAtIdx(i * 64 + n, CHAR_DATA[i][n]);
	}
}

console.log(memoryAsInt32);

////////////////////////////////////////////////////////////////////////
// WASM has internal blob of memory 192kb in size. It includes the pixel
// contents of the frame.
// We need to take the pixel contents region of the memory and display it
// on the screen.
// Create fullscreen WebGL quad and use it to cover the canvas
////////////////////////////////////////////////////////////////////////
const glProgram = createProgram(
	gl,
	`#version 300 es
  in vec4 aPosition;
  in vec2 aUV;
  out vec2 vUV;
  void main() {
    gl_Position = aPosition;
    vUV = aUV;
  }
  `,
	`#version 300 es
  precision highp float;
  precision highp isampler2D;
  uniform isampler2D uTex;
  in vec2 vUV;
  out vec4 finalColor;
  int fetchPixel(vec2 uv) {
    vec2 texSize = vec2(${CANVAS_WIDTH}, ${CANVAS_HEIGHT});
    ivec4 color = texelFetch(uTex, ivec2(uv * texSize), 0);
    return color.r;
  }
  void main () {
    ivec2 texSize = textureSize(uTex, 0);
    finalColor = vec4(vec3(fetchPixel(vUV)) / 255.0, 1.0);
  }
  `,
	{},
);

const planeGeometry = createPlane({ width: 2, height: 2 });
const planeBuffer = gl.createBuffer();
gl.bindBuffer(gl.ARRAY_BUFFER, planeBuffer);
gl.bufferData(gl.ARRAY_BUFFER, planeGeometry.interleavedArray, gl.STATIC_DRAW);
const aPosAttrib = gl.getAttribLocation(glProgram, "aPosition");
const aUvAttrib = gl.getAttribLocation(glProgram, "aUV");
gl.vertexAttribPointer(
	aPosAttrib,
	3,
	gl.FLOAT,
	false,
	planeGeometry.vertexStride * Float32Array.BYTES_PER_ELEMENT,
	0,
);
gl.vertexAttribPointer(
	aUvAttrib,
	2,
	gl.FLOAT,
	false,
	planeGeometry.vertexStride * Float32Array.BYTES_PER_ELEMENT,
	3 * Float32Array.BYTES_PER_ELEMENT,
);
const planeIndexBuffer = gl.createBuffer();
gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, planeIndexBuffer);
gl.bufferData(
	gl.ELEMENT_ARRAY_BUFFER,
	planeGeometry.indicesArray,
	gl.STATIC_DRAW,
);

const uTexture = gl.getUniformLocation(glProgram, "uTex");
const texture = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texture);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

gl.useProgram(glProgram);
gl.uniform1i(uTexture, 0);

////////////////////////////////////////////////////////////////////////
// Start game
////////////////////////////////////////////////////////////////////////
exports.setSnakeMovementState(snakeState);
document.body.addEventListener("keydown", (e) => {
	let newState: SnakeMoveState;
	switch (e.key) {
		case "ArrowUp":
			e.preventDefault();
			newState = 0;
			break;
		case "ArrowRight":
			e.preventDefault();
			newState = 1;
			break;
		case "ArrowDown":
			e.preventDefault();
			newState = 2;
			break;
		case "ArrowLeft":
			e.preventDefault();
			newState = 3;
			break;
		default:
			return;
	}
	if (!canChangeSnakeState) {
		return;
	}
	canChangeSnakeState = false;

	if (snakeState === 0 || snakeState === 2) {
		if (newState === 1 || newState === 3) {
			snakeState = newState;
		}
	}
	if (snakeState === 1 || snakeState === 3) {
		if (newState === 0 || newState === 2) {
			snakeState = newState;
		}
	}
	exports.setSnakeMovementState(snakeState);
});

setInterval(drawFrame, 1000 / FPS);

function drawFrame() {
	// Update WASM pixel contents memory
	exports.updateFrame();

	// Upload WASM pixel contents to GPU and blit them to the screen
	gl.texImage2D(
		gl.TEXTURE_2D,
		0,
		gl.R32I,
		CANVAS_WIDTH,
		CANVAS_HEIGHT,
		0,
		gl.RED_INTEGER,
		gl.INT,
		memoryAsInt32,
	);

	gl.enableVertexAttribArray(aPosAttrib);
	gl.enableVertexAttribArray(aUvAttrib);
	gl.viewport(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);
	gl.drawElements(
		gl.TRIANGLES,
		planeGeometry.vertexCount,
		gl.UNSIGNED_SHORT,
		0,
	);

	canChangeSnakeState = true;
}
