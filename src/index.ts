import snakeWasmURL from "./snake.wasm?url";

import { createPlane, createProgram } from "./lib/hwoa-rang-gl2";

const CANVAS_WIDTH = 256;
const CANVAS_HEIGHT = 128;

const $glContiner = document.getElementById("gl-container")!;
const $c = document.createElement("canvas") as HTMLCanvasElement;
const gl = $c.getContext("webgl2")!;

$c.width = CANVAS_WIDTH;
$c.height = CANVAS_HEIGHT;
$c.setAttribute("id", "c");
$glContiner.appendChild($c);

const { module, instance } = await WebAssembly.instantiateStreaming(
	fetch(snakeWasmURL),
	{},
);

console.log(new Int32Array(instance.exports.memory.buffer));

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

gl.viewport(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT);

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

const uTexture = gl.getUniformLocation(glProgram, "uTex");

const planeIndexBuffer = gl.createBuffer();
gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, planeIndexBuffer);
gl.bufferData(
	gl.ELEMENT_ARRAY_BUFFER,
	planeGeometry.indicesArray,
	gl.STATIC_DRAW,
);

gl.useProgram(glProgram);
gl.uniform1i(uTexture, 0);

gl.enableVertexAttribArray(aPosAttrib);
gl.enableVertexAttribArray(aUvAttrib);

const texture = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texture);
gl.texImage2D(
	gl.TEXTURE_2D,
	0,
	gl.R32I,
	CANVAS_WIDTH,
	CANVAS_HEIGHT,
	0,
	gl.RED_INTEGER,
	gl.INT,
	new Int32Array(instance.exports.memory.buffer),
);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
gl.activeTexture(gl.TEXTURE0);
gl.drawElements(gl.TRIANGLES, planeGeometry.vertexCount, gl.UNSIGNED_SHORT, 0);
