# SystemVerilog_implementation_of_NoC_Router
Synthesizable SystemVerilog RTL implementation of NVIDIA's SystemC-based NoC Router (HybridRouter.h)

## Summary
This work is a SystemVerilog RTL implementation of the [HybridRouter.h](https://github.com/NVlabs/matchlib/blob/hybrid_router/cmod/include/HybridRouter.h#L1847),
which is presumably the NoC Router used in NVIDIA's paper, Simba ([Paper](https://dl.acm.org/doi/10.1145/3352460.3358302), [Presentation](https://research.nvidia.com/sites/default/files/pubs/2019-08_A-0.11-pJ/Op%2C//HotChips_RC18_final.pdf))

Originally, this router has the following features:
- It has a hierarchical structure of two mesh topologies (a 2D mesh for NoP and a 2D mesh for NoC).
- Routing is performed using XY DOR.
- Flow control is performed using wormhole for unicast and cut-through for multicast.
- Arbitration is performed by round-robin among unicast and by cut-through among multicast, with multicast being prioritized over unicast.
- The round-robin arbiter specifically operates with a priority rotation in descending order (from MSB to LSB).
- It does not use virtual channels.
- It is an output-buffered structure.
- It has a 4-cycle latency. The pipeline stages consist of: writing to the input port register → Reading for Route Computation, Switch Allocation, and Switch Traversal and writing to the output buffer → Moving from the output buffer to the output port register → Finally moving out of the router.
- It uses ready/valid handshaking for backpressure instead of credit.

In this work, the following have been changed:
- Modified the network topology to a flat 2D mesh.
- Removed the pipeline stage at the output port.
- Modified the arbiter priority from descending order (MSB to LSB) to ascending order (LSB to MSB) for round robin rotation.
