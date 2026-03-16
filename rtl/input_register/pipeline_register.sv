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
 

module pipeline_register #(
    parameter   WIDTH = 258
) (
    input  logic             clk,
    input  logic             rst,

    input  logic             in_valid,
    output logic             in_ready,
    input  logic [WIDTH-1:0] in_data,

    output logic             out_valid,
    input  logic             out_ready,
    output logic [WIDTH-1:0] out_data
);

    logic             is_valid;
    logic [WIDTH-1:0] data;

    always_ff @(posedge clk) begin
        if (in_valid && in_ready)
            data <= in_data;
    end

    always_ff @(posedge clk) begin
        if (rst)
            is_valid <= 1'b0;
        else if (in_valid && in_ready)
            is_valid <= 1'b1;
        else if (out_valid && out_ready) // !(in_valid && in_ready) && (out_valid && out_ready)
            is_valid <= 1'b0;
    end

    assign in_ready = ~out_valid | out_ready; // !is_valid || (out_valid && out_ready);
    assign out_valid = is_valid;
    assign out_data = data;

endmodule