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

interface switch_allocation_if
(
    input logic clk
);

    logic           [NUM_PORTS-1:0] in_valid;
    flit_type_t     [NUM_PORTS-1:0] flit_type;
    is_mcast_t      [NUM_PORTS-1:0] is_mcast;
    obuf_depth_t    [NUM_PORTS-1:0] obuf_num_free;
    port_mask_t     [NUM_PORTS-1:0] request;

    port_mask_t     [NUM_PORTS-1:0] grant;
    port_index_t    [NUM_PORTS-1:0] grant_id;

    modport router
    (
        output in_valid,
        output flit_type,
        output is_mcast,
        output obuf_num_free,
        output request,

        input grant,
        input grant_id
    );

    modport sa
    (
        input in_valid,
        input flit_type,
        input is_mcast,
        input obuf_num_free,
        input request,

        output grant,
        output grant_id
    );

    clocking driver_cb @(posedge clk);
        default input #1step output #0;

        output in_valid;
        output flit_type;
        output is_mcast;
        output obuf_num_free;
        output request;

        input grant;
        input grant_id;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1step;

        input in_valid;
        input flit_type;
        input is_mcast;
        input obuf_num_free;
        input request;
        input grant;
        input grant_id;
    endclocking

endinterface