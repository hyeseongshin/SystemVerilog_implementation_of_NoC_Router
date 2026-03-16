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

interface hybrid_router_if
(
    input logic             clk
);

    /* LUT configuration */
    logic                   cfg_valid;
    logic                   cfg_ready;
    port_mask_t             cfg_data;

    /* router input interface */
    logic   [NUM_PORTS-1:0] in_valid;
    logic   [NUM_PORTS-1:0] in_ready;
    flit_t  [NUM_PORTS-1:0] in_data;

    /* router output interface */
    logic   [NUM_PORTS-1:0] out_valid;
    logic   [NUM_PORTS-1:0] out_ready;
    flit_t  [NUM_PORTS-1:0] out_data;

    modport router
    (
        input   cfg_valid,
        output  cfg_ready,
        input   cfg_data,

        input   in_valid,
        output  in_ready,
        input   in_data,

        output  out_valid,
        input   out_ready,
        output  out_data
    );

    modport network
    (
        output  cfg_valid,
        input   cfg_ready,
        output  cfg_data,

        output  in_valid,
        input   in_ready,
        output  in_data,
        
        input   out_valid,
        output  out_ready,
        input   out_data
    );

    clocking driver_cb @(posedge clk);
        default input #1step output #0;

        output  cfg_valid;
        input   cfg_ready;
        output  cfg_data;

        output  in_valid;
        input   in_ready;
        output  in_data;
        
        input   out_valid;
        output  out_ready;
        input   out_data;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;

        input cfg_valid;
        input cfg_ready;
        input cfg_data;

        input in_valid;
        input in_ready;
        input in_data;
        
        input out_valid;
        input out_ready;
        input out_data;
    endclocking

endinterface
