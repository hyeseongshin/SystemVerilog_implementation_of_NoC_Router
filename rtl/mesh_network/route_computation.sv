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

module route_computation
(
    input logic                 clk,
    input logic                 rst,

    route_computation_if.rc     rc_if
);

    port_mask_t  [NUM_PORTS-1:0]    new_request;
    port_mask_t  [NUM_PORTS-1:0]    reg_request;
    port_mask_t  [WIDTH_DEST-1:0]   dest_LUT;

    cfg_state_t                     curr_state;
    cfg_state_t                     next_state;
    logic [$clog2(WIDTH_DEST)-1:0]  cnt;

    // FSM for look-up table configuration
    always_ff @(posedge clk) begin
        if (rst)
            curr_state <= RST_CFG;
        else
            curr_state <= next_state;
    end

    always_comb begin
        case (curr_state)
            RST_CFG:
                next_state = WAIT_CFG;
            WAIT_CFG:
                if (rc_if.cfg_valid && (cnt == WIDTH_DEST-1))
                    next_state = DONE_CFG;
                else
                    next_state = WAIT_CFG;
            DONE_CFG:
                if (rc_if.cfg_valid)
                    next_state = WAIT_CFG;
                else
                    next_state = DONE_CFG;
            default: 
                next_state = RST_CFG;
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst)
            cnt <= 0;
        else if (rc_if.cfg_valid && rc_if.cfg_ready)
            cnt <= cnt + 1;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            dest_LUT <= '0;
        end
        else if (rc_if.cfg_valid && rc_if.cfg_ready) begin
            dest_LUT[cnt] <= rc_if.cfg_data;
        end
    end

    assign rc_if.cfg_ready = (curr_state == WAIT_CFG);
    

    // create mask for masking destination field for routing of next router
    always_comb begin
        for (int i = 0; i < WIDTH_DEST; i++) begin
            for (int k = 0; k < NUM_PORTS; k++) begin
                rc_if.mask[k][i] = (curr_state == DONE_CFG) ? dest_LUT[i][k] : '0;
            end
        end
    end


    // route computation logics
    // check all bits of dest (one-hot(unicast)/multi-hot(multicast) encoding)
    always_comb begin
        new_request = '0;
        for (int i = 0; i < NUM_PORTS; i++) begin
            for (int j = 0; j < WIDTH_DEST; j++)
                if ((curr_state == DONE_CFG) && rc_if.in_valid[i] && rc_if.dest[i][j])
                    new_request[i] = new_request[i] | dest_LUT[j];
        end
    end


    // because destination field exists only in head flit,
    // route computation results are stored in register
    always_ff @(posedge clk) begin
        if (rst)
            reg_request <= '0;
        else begin
            for (int i = 0; i < NUM_PORTS; i++) begin
                if ((curr_state == DONE_CFG) && rc_if.in_valid[i] && (rc_if.flit_type[i] == HEAD))
                    reg_request[i] <= new_request[i]; 
            end
        end
    end


    // because destination field exists only in head flit
    // the head flit uses the route computation result and body, tail flit uses the register value
    always_comb begin
        for (int i = 0; i < NUM_PORTS; i++)
            rc_if.request[i] = (rc_if.flit_type[i] == HEAD) ? new_request[i] : reg_request[i];
    end

endmodule