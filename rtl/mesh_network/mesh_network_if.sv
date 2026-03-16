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
 

import setting_noc::*;

interface mesh_network_if
(
    input logic clk
);

    /* LUT configuration */
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] cfg_valid;
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] cfg_ready;
    port_mask_t [NUM_ROWS-1:0][NUM_COLS-1:0] cfg_data;

    /* pe -> router */
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] pe_out_valid;
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] pe_out_ready;
    flit_t      [NUM_ROWS-1:0][NUM_COLS-1:0] pe_out_data;

    /* router -> pe */
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] pe_in_valid;
    logic       [NUM_ROWS-1:0][NUM_COLS-1:0] pe_in_ready;
    flit_t      [NUM_ROWS-1:0][NUM_COLS-1:0] pe_in_data;

    modport router
    (
        input   cfg_valid,
        output  cfg_ready,
        input   cfg_data,

        input   pe_out_valid,
        output  pe_out_ready,
        input   pe_out_data,

        output  pe_in_valid,
        input   pe_in_ready,
        output  pe_in_data
    );

    modport pe
    (
        output  cfg_valid,
        input   cfg_ready,
        output  cfg_data,

        output  pe_out_valid,
        input   pe_out_ready,
        output  pe_out_data,

        input   pe_in_valid,
        output  pe_in_ready,
        input   pe_in_data
    );

    clocking driver_cb @(posedge clk);
        default input #1step output #0;

        output  cfg_valid;
        input   cfg_ready;
        output  cfg_data;

        output  pe_out_valid;
        input   pe_out_ready;
        output  pe_out_data;

        input   pe_in_valid;
        output  pe_in_ready;
        input   pe_in_data;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;

        input cfg_valid;
        input cfg_ready;
        input cfg_data;

        input pe_out_valid;
        input pe_out_ready;
        input pe_out_data;

        input pe_in_valid;
        input pe_in_ready;
        input pe_in_data;
    endclocking
    
endinterface