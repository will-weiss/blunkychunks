/**
 * blunkychunks — procedurally generated connected triangle shapes.
 *
 * Coordinates
 * -----------
 * Triangles live on the faces of a triangular tiling, which are indexed here by
 * Eisenstein integers: a cell (a, b) means z = a + b·ω, where ω = e^(2πi/3).
 *
 * The faces of the triangular tiling form a honeycomb (hexagonal) lattice, and
 * the honeycomb is exactly the Eisenstein integers with the residue class
 * z ≡ 0 (mod λ) removed, where λ = 1 - ω. Since z = a + bω ≡ a + b (mod λ) and
 * Z[ω]/λ ≅ Z/3, that residue is just (a + b) mod 3. We drop the class 1 rather
 * than 0, so that the origin (0, 0) is a valid triangle:
 *
 *   (a + b) mod 3 === 0  →  a ▽ triangle
 *   (a + b) mod 3 === 2  →  a △ triangle
 *   (a + b) mod 3 === 1  →  not a cell
 *
 * Two cells share an edge iff they differ by an Eisenstein unit, which gives
 * each cell exactly three neighbours (see `neighbors`).
 *
 * CLI
 * ---
 *   deno run blunkychunks.ts > chunks.svg      # 10 chunks as one SVG
 *   deno run blunkychunks.ts --json            # the raw (a, b, color) tuples
 *   deno run blunkychunks.ts --count 10 --size 14 --seed 42
 *
 * (`bun blunkychunks.ts` / `npx tsx blunkychunks.ts` work the same way.)
 */

export const COLORS = ["red", "green", "blue"] as const;
export type Color = (typeof COLORS)[number];

/** A single triangle: Eisenstein coordinates plus its color. */
export type Chunk = [a: number, b: number, c: Color];

const SQRT3 = Math.sqrt(3);

/** Non-negative remainder mod 3. */
function mod3(n: number): number {
  return ((n % 3) + 3) % 3;
}

/** Is (a, b) a triangle of the tiling? */
export function isCell(a: number, b: number): boolean {
  return mod3(a + b) !== 1;
}

/** The three edge-sharing neighbours of a cell. */
export function neighbors(a: number, b: number): [number, number][] {
  const r = mod3(a + b);
  if (r === 1) throw new Error(`(${a}, ${b}) is not a triangle cell`);
  // ▽ cells subtract a unit, △ cells add one; either way the residue flips.
  return r === 0
    ? [[a - 1, b], [a, b - 1], [a + 1, b + 1]]
    : [[a + 1, b], [a, b + 1], [a - 1, b - 1]];
}

/** Deterministic PRNG (mulberry32), so a seed reproduces a chunk exactly. */
export function seededRandom(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface ChunkOptions {
  /** Seed for reproducible output. Ignored if `rng` is given. */
  seed?: number;
  /** Custom uniform [0, 1) source. */
  rng?: () => number;
}

/**
 * Grow a connected blunkychunk of `size` triangles, rooted at the origin.
 *
 * Every pair of edge-sharing triangles gets different colors. Growth is an
 * Eden model: repeatedly pick a uniformly random frontier cell, color it with
 * a color none of its placed neighbours use, and extend the frontier.
 */
export function blunkychunks(size: number, options: ChunkOptions = {}): Chunk[] {
  if (!Number.isInteger(size) || size < 1) {
    throw new Error(`size must be a positive integer, got ${size}`);
  }
  const rng = options.rng ?? (options.seed === undefined ? Math.random : seededRandom(options.seed));
  const pick = <T>(xs: readonly T[]): T => xs[Math.floor(rng() * xs.length)];

  const key = (a: number, b: number) => `${a},${b}`;
  const placed = new Map<string, Color>();
  const chunk: Chunk[] = [];
  const frontier: [number, number][] = [];

  const place = (a: number, b: number, color: Color) => {
    placed.set(key(a, b), color);
    chunk.push([a, b, color]);
    for (const [na, nb] of neighbors(a, b)) {
      if (!placed.has(key(na, nb))) frontier.push([na, nb]);
    }
  };

  place(0, 0, pick(COLORS));

  while (chunk.length < size && frontier.length > 0) {
    // Swap-remove a random frontier entry.
    const i = Math.floor(rng() * frontier.length);
    const [a, b] = frontier[i];
    frontier[i] = frontier[frontier.length - 1];
    frontier.pop();
    if (placed.has(key(a, b))) continue; // queued more than once

    const taken = new Set<Color>();
    for (const [na, nb] of neighbors(a, b)) {
      const c = placed.get(key(na, nb));
      if (c) taken.add(c);
    }
    const available = COLORS.filter((c) => !taken.has(c));
    // A cell walled in by all three colors can never be colored — drop it.
    if (available.length === 0) continue;

    place(a, b, pick(available));
  }

  return chunk;
}

/* ------------------------------ rendering ------------------------------- */

/**
 * The three corners of a cell, in SVG space (y down). `side` is the triangle's
 * edge length. The Eisenstein plane is rotated a quarter turn so that the
 * triangles sit point-up / point-down, matching the game board.
 */
export function cellCorners(a: number, b: number, side = 1): [number, number][] {
  const r = mod3(a + b);
  if (r === 1) throw new Error(`(${a}, ${b}) is not a triangle cell`);
  const scale = side / SQRT3; // circumradius of a triangle with this edge
  const cx = a - b / 2; // centroid = a·1 + b·ω
  const cy = (b * SQRT3) / 2;
  const base = r === 0 ? 0 : 60;
  return [0, 120, 240].map((d) => {
    const t = ((base + d) * Math.PI) / 180;
    // (x, y) → (y, x) rotates by -90° and flips y for SVG's downward axis.
    return [(cy + Math.sin(t)) * scale, (cx + Math.cos(t)) * scale] as [number, number];
  });
}

const FILL: Record<Color, string> = {
  red: "#d6494f",
  green: "#3f9a55",
  blue: "#3f68c4",
};

export interface RenderOptions {
  /** Triangle edge length in px. */
  side?: number;
  /** Chunks per row in the layout grid. */
  columns?: number;
  /** Space between and around chunks, in px. */
  gap?: number;
  background?: string;
  stroke?: string;
}

interface Placed {
  paths: string[];
  width: number;
  height: number;
}

function layoutChunk(chunk: Chunk[], side: number, stroke: string): Placed {
  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const corners = chunk.map(([a, b]) => cellCorners(a, b, side));
  for (const tri of corners) {
    for (const [x, y] of tri) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  const paths = corners.map((tri, i) => {
    const pts = tri.map(([x, y]) => `${(x - minX).toFixed(3)},${(y - minY).toFixed(3)}`).join(" ");
    return `<polygon points="${pts}" fill="${FILL[chunk[i][2]]}" stroke="${stroke}"/>`;
  });
  return { paths, width: maxX - minX, height: maxY - minY };
}

/** Render one or more blunkychunks into a single SVG document. */
export function toSVG(chunks: Chunk[] | Chunk[][], options: RenderOptions = {}): string {
  const {
    side = 40,
    columns = 5,
    gap = 32,
    background = "#ffffff",
    stroke = "#1f2933",
  } = options;

  const all: Chunk[][] = Array.isArray(chunks[0]) ? (chunks as Chunk[][]) : [chunks as Chunk[]];
  const placed = all.map((c) => layoutChunk(c, side, stroke));
  const cols = Math.min(columns, placed.length);
  const rows = Math.ceil(placed.length / cols);

  // Uniform cells, sized by the largest chunk, so nothing overlaps.
  const cellW = Math.max(...placed.map((p) => p.width));
  const cellH = Math.max(...placed.map((p) => p.height));
  const width = gap + cols * (cellW + gap);
  const height = gap + rows * (cellH + gap);

  const groups = placed.map((p, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const x = gap + col * (cellW + gap) + (cellW - p.width) / 2;
    const y = gap + row * (cellH + gap) + (cellH - p.height) / 2;
    return `  <g transform="translate(${x.toFixed(3)} ${y.toFixed(3)})">\n    ${
      p.paths.join("\n    ")
    }\n  </g>`;
  });

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width.toFixed(3)} ${
      height.toFixed(3)
    }" width="${width.toFixed(0)}" height="${height.toFixed(0)}">`,
    `  <rect width="100%" height="100%" fill="${background}"/>`,
    `  <g stroke-width="1.25" stroke-linejoin="round">`,
    ...groups,
    `  </g>`,
    `</svg>`,
  ].join("\n");
}

/* --------------------------------- CLI ---------------------------------- */

function argv(): string[] {
  const d = (globalThis as { Deno?: { args: string[] } }).Deno;
  if (d) return d.args;
  const p = (globalThis as { process?: { argv: string[] } }).process;
  return p ? p.argv.slice(2) : [];
}

function main(args: string[]): void {
  const flag = (name: string, fallback: number): number => {
    const i = args.indexOf(`--${name}`);
    if (i === -1) return fallback;
    const v = Number(args[i + 1]);
    if (!Number.isFinite(v)) throw new Error(`--${name} needs a number`);
    return v;
  };

  const count = flag("count", 10);
  const size = flag("size", 14);
  const side = flag("side", 40);
  const hasSeed = args.includes("--seed");
  const seed = flag("seed", 0);

  const chunks: Chunk[][] = [];
  for (let i = 0; i < count; i++) {
    chunks.push(blunkychunks(size, hasSeed ? { seed: seed + i } : {}));
  }

  console.log(args.includes("--json") ? JSON.stringify(chunks) : toSVG(chunks, { side }));
}

const isMain = (globalThis as { Deno?: { mainModule: string } }).Deno
  ? (import.meta as { main?: boolean }).main === true
  : (globalThis as { process?: { argv: string[] } }).process?.argv[1] !== undefined &&
    import.meta.url === `file://${(globalThis as { process: { argv: string[] } }).process.argv[1]}`;

if (isMain) main(argv());
