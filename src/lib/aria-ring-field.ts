import { drawAriaNest, type NestDrawInput } from "./aria-nest";

/** @deprecated Brand renderer is `drawAriaNest`. Kept as a compile shim. */
export type RingFieldDrawInput = NestDrawInput;

/**
 * @deprecated Kinetic 5-ellipse ring-field is retired as the brand mark.
 * Calls through to the B+E soft-hex nest so leftover imports stay on-contract.
 */
export function drawAriaRingField(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  input: RingFieldDrawInput
): void {
  drawAriaNest(ctx, width, height, input);
}
