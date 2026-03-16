/*
 * Copyright (c) 2026, Hyeseong Shin (hyeseongshin@konkuk.ac.kr)
 * All rights reserved.
 * This work is a SystemVerilog implementation based on the original 
 * SystemC source code provided by NVIDIA CORPORATION.
 * Source: https://github.com/NVlabs/matchlib/blob/hybrid_router/cmod/include/HybridRouter.h#L1847
 *
 * ------------------------------------------------------------------------------
 * NOTE: This work has been modified from the original source code.
 * Changes:
 * - Modified the network topology to a flat 2D mesh.
 * - Remove the pipeline stage at the output port.
 * - Modified the arbiter priority from descending order (MSB to LSB)
 *   to ascending order (LSB to MSB) for round robin rotation.
 * ------------------------------------------------------------------------------
 *
 * Original Work Copyright (c) 2016-2019, NVIDIA CORPORATION. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License")
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
 

module round_robin_arbiter #(
    parameter NUM_REQS = 5
) (
    input   logic                   clk,
    input   logic                   rst,

    /* input ports */
    input   logic   [NUM_REQS-1:0]  request,

    /* output ports */
    output  logic   [NUM_REQS-1:0]  grant
);

    logic   [NUM_REQS-1:0] masked_request;
    logic   [NUM_REQS-1:0] masked_grant;
    logic   [NUM_REQS-1:0] unmasked_grant;

    logic   [NUM_REQS-1:0] mask;

    assign masked_request = request & mask;
    assign masked_grant = masked_request & -masked_request;
    assign unmasked_grant = request & -request;
    assign grant = (|masked_request) ? masked_grant : unmasked_grant;

    always_ff @(posedge clk) begin
        if (rst)
            mask <= '1;
        else if (|request)
            mask <= ~(grant | (grant - 1));
    end

endmodule
