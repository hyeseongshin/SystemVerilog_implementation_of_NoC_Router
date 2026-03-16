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

module mesh_network 
(
    input   logic           clk,
    input   logic           rst,

    mesh_network_if.router  network_if
);

    // if `NUM_COLS = 4, `NUM_ROWS = 3,
    // 0 - 1 - 2 - 3
    // |   |   |   |
    // 4 - 5 - 6 - 7
    // |   |   |   |
    // 8 - 9 - 10 - 11


    /* router inputs */
    logic   [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_in_valid;
    flit_t  [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_in_data;
    logic   [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_out_ready;

    /* router outputs */
    logic   [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_in_ready;
    logic   [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_out_valid;
    flit_t  [NUM_ROWS-1:0][NUM_COLS-1:0][NUM_PORTS-1:0] router_out_data;

    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_row
        for (genvar c = 0; c < NUM_COLS; c++) begin : gen_col
            // local port
            assign router_in_valid  [r][c][LOCAL_PORT_NUM] = network_if.pe_out_valid[r][c];
            assign router_in_data   [r][c][LOCAL_PORT_NUM] = network_if.pe_out_data[r][c];
            assign router_out_ready [r][c][LOCAL_PORT_NUM] = network_if.pe_in_ready[r][c];

            // north port
            assign router_in_valid  [r][c][NORTH_PORT_NUM] = (r > 0) ? router_out_valid[r - 1][c][SOUTH_PORT_NUM] : '0;
            assign router_in_data   [r][c][NORTH_PORT_NUM] = (r > 0) ? router_out_data [r - 1][c][SOUTH_PORT_NUM] : '0;
            assign router_out_ready [r][c][NORTH_PORT_NUM] = (r > 0) ? router_in_ready [r - 1][c][SOUTH_PORT_NUM] : '0;

            // east port
            assign router_in_valid  [r][c][EAST_PORT_NUM] = (c < (NUM_COLS - 1)) ? router_out_valid[r][c + 1][WEST_PORT_NUM] : '0;
            assign router_in_data   [r][c][EAST_PORT_NUM] = (c < (NUM_COLS - 1)) ? router_out_data [r][c + 1][WEST_PORT_NUM] : '0;
            assign router_out_ready [r][c][EAST_PORT_NUM] = (c < (NUM_COLS - 1)) ? router_in_ready [r][c + 1][WEST_PORT_NUM] : '0;

            // south port
            assign router_in_valid  [r][c][SOUTH_PORT_NUM] = (r < (NUM_ROWS - 1)) ? router_out_valid[r + 1][c][NORTH_PORT_NUM] : '0;
            assign router_in_data   [r][c][SOUTH_PORT_NUM] = (r < (NUM_ROWS - 1)) ? router_out_data [r + 1][c][NORTH_PORT_NUM] : '0;
            assign router_out_ready [r][c][SOUTH_PORT_NUM] = (r < (NUM_ROWS - 1)) ? router_in_ready [r + 1][c][NORTH_PORT_NUM] : '0;

            // west port
            assign router_in_valid  [r][c][WEST_PORT_NUM] = (c > 0) ? router_out_valid[r][c - 1][EAST_PORT_NUM] : '0;
            assign router_in_data   [r][c][WEST_PORT_NUM] = (c > 0) ? router_out_data [r][c - 1][EAST_PORT_NUM] : '0;
            assign router_out_ready [r][c][WEST_PORT_NUM] = (c > 0) ? router_in_ready [r][c - 1][EAST_PORT_NUM] : '0;


            hybrid_router_if router_if(.clk(clk));
            assign router_if.cfg_valid = network_if.cfg_valid[r][c];
            assign router_if.cfg_data  = network_if.cfg_data[r][c];
            assign router_if.in_valid  = router_in_valid[r][c];
            assign router_if.in_data   = router_in_data[r][c];
            assign router_if.out_ready = router_out_ready[r][c];

            assign network_if.cfg_ready[r][c]   = router_if.cfg_ready;
            assign router_in_ready[r][c]        = router_if.in_ready;
            assign router_out_valid[r][c]       = router_if.out_valid;
            assign router_out_data[r][c]        = router_if.out_data;

            hybrid_router #(.ROUTER_ID(r * NUM_COLS + c)) router (
                .clk(clk),
                .rst(rst),
                .router_if(router_if.router)
            );

            assign network_if.pe_out_ready[r][c]    = router_in_ready[r][c][LOCAL_PORT_NUM];
            assign network_if.pe_in_valid[r][c]     = router_out_valid[r][c][LOCAL_PORT_NUM];
            assign network_if.pe_in_data[r][c]      = router_out_data[r][c][LOCAL_PORT_NUM];
        end
    end

endmodule