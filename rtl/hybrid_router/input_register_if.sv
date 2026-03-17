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
 * - Removed the pipeline stage at the output port.
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
 

import setting_noc::*;

interface input_register_if
(
    input logic clk
);

    logic           in_valid;
    logic           in_ready;
    flit_t          in_data;

    logic           out_valid;
    logic           out_ready;
    flit_t          out_data;


    modport ireg
    (
        input   in_valid,
        output  in_ready,
        input   in_data,

        output  out_valid,
        input   out_ready,
        output  out_data
    );

    modport router
    (
        output  in_valid,
        input   in_ready,
        output  in_data,

        input   out_valid,
        output  out_ready,
        input   out_data
    );


    clocking driver_cb @(posedge clk);
        default input #1step output #0;

        output   in_valid;
        output   in_ready;
        output   in_data;

        input   out_valid;
        output  out_ready;
        input   out_data;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;

        input  in_valid;
        input  in_ready;
        input  in_data;

        input  out_valid;
        input  out_ready;
        input  out_data;
    endclocking

endinterface