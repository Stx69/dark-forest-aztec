declare module "@alejoamiras/aztec-accelerator" {
  export type AcceleratorProverOptions = {
    accelerator: { port: number; host: string };
    onPhase?: (phase: string, data: unknown) => void;
  };

  export class AcceleratorProver {
    constructor(options: AcceleratorProverOptions);
  }
}
