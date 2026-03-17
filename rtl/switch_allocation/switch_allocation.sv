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

module switch_allocation (
    input logic                 clk,
    input logic                 rst,
    
    switch_allocation_if.sa     sa_if
);

    is_mcast_t      [NUM_PORTS-1:0] is_mcast_pkt;
    logic           [NUM_PORTS-1:0] is_wh_avail;
    logic           [NUM_PORTS-1:0] is_ct_avail;

    port_mask_t     [NUM_PORTS:0]   occupied_mcast;
    port_mask_t     [NUM_PORTS-1:0] valid_mcast;
    port_mask_t     [NUM_PORTS-1:0] grant_mcast;

    port_mask_t     [NUM_PORTS-1:0] valid_ucast;
    port_mask_t     [NUM_PORTS-1:0] valid_ucast_transposed;
    port_mask_t     [NUM_PORTS-1:0] grant_ucast;

    port_mask_t     [NUM_PORTS-1:0] grant_result;
    port_index_t    [NUM_PORTS-1:0] grant_id_result;

    is_mcast_t      [NUM_PORTS-1:0] is_mcast_reg;
    logic           [NUM_PORTS-1:0] is_obuf_busy_reg;


    always_comb begin
        // identify whether the flit belongs to the multicast packet or unicast packet
        // (is_mcast flag exists only in the head flit)
        for (int i = 0; i < NUM_PORTS; i++) begin
            is_mcast_pkt[i]  = (sa_if.flit_type[i] == HEAD) ? sa_if.is_mcast[i] : is_mcast_reg[i];
        end

        // check output buffer condition (wh = wormhole, ct = cut-through)
        for (int k = 0; k < NUM_PORTS; k++) begin
            is_wh_avail[k] = (sa_if.obuf_num_free[k] >= 1);
            is_ct_avail[k] = (sa_if.obuf_num_free[k] >= MAX_PKT_LEN);
        end
    end


    // request -> valid 
    // logic that checks whether wormhole (unicast) and cut-through (multicast) conditions are met or not
    // for multicast packet, additional check of whether conditions are satisfied for all output buffers or not
    for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_valid
        logic       is_not_head;
        port_mask_t mask_mcast;
        port_mask_t valid_mcast_tmp;
        port_mask_t mask_ucast;
        
        assign is_not_head     = (sa_if.flit_type[i] != HEAD);

        // multicast packet follows cut-through
        // for head flit, it checks buffer occupancy and available space for a packet
        // for body or tail flit, bypass further checks as cut-through conditions already checked by head flit
        assign mask_mcast      = ({NUM_PORTS{is_not_head}} | (~is_obuf_busy_reg & is_ct_avail));
        //signals to check if any request of a multicast packet has failed
        assign valid_mcast_tmp = sa_if.request[i] & mask_mcast;
        
        // unicast packet follows wormhole
        // for head, body and tail flit, it checks available space for a flit
        // and for head flit, it checks buffer occupancy
        // for body or tail flit, bypass buffer occupancy checking as buffer occupancy already checked by head flit
        assign mask_ucast      = is_wh_avail & ({NUM_PORTS{is_not_head}} | ~is_obuf_busy_reg);

        always_comb begin
            valid_mcast[i] = '0;
            valid_ucast[i] = '0;

            if (sa_if.in_valid[i]) begin
                if (is_mcast_pkt[i]) begin
                    // for a multicast packet, all requests must be valid
                    if (valid_mcast_tmp == sa_if.request[i])
                        valid_mcast[i] = sa_if.request[i];
                end
                else
                    valid_ucast[i] = sa_if.request[i] & mask_ucast;
            end
        end
    end


    // valid_mcast -> grant_mcast
    // multicast packet has priority, fixed priority among multicasts
    always_comb begin
        port_mask_t [NUM_PORTS-1:0] grant_mcast_transposed;
        occupied_mcast[0] = '0;
        for (int i = 0; i < NUM_PORTS; i++) begin
            grant_mcast_transposed[i] = ((occupied_mcast[i] & valid_mcast[i]) == 0) ? valid_mcast[i] : '0;
            
            occupied_mcast[i+1] = occupied_mcast[i] | grant_mcast_transposed[i];
        end

        foreach (grant_mcast[k, i]) begin
            grant_mcast[k][i] = grant_mcast_transposed[i][k];
        end
    end


    // valid_ucast -> grant_ucast
    // instantiate round-robin arbiters, round-robin among unicasts
    for (genvar k = 0; k < NUM_PORTS; k++) begin : gen_arb
        for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_arb_input
            assign valid_ucast_transposed[k][i] = valid_ucast[i][k] & ~occupied_mcast[NUM_PORTS][k];
        end

        round_robin_arbiter arb_ucast (
            .clk(clk),
            .rst(rst),
            .request(valid_ucast_transposed[k]),

            .grant(grant_ucast[k])
        );
    end


    // grant_mcast, grant_ucast -> grant, grant_id
    always_comb begin
        grant_id_result = '0;
        for (int k = 0; k < NUM_PORTS; k++) begin
            grant_result[k] = grant_mcast[k] | grant_ucast[k];

            for (int i = 0; i < NUM_PORTS; i++)
                grant_id_result[k] |= {$bits(port_index_t){grant_result[k][i]}} & port_index_t'(i);
        end
    end

    assign sa_if.grant      = grant_result;
    assign sa_if.grant_id   = grant_id_result;


    // update register
    // because is_mcast flag exists only in the head flit, it is stored in register
    always_ff @(posedge clk) begin
        if (rst)
            is_mcast_reg <= '0;
        else begin
            for (int i = 0; i < NUM_PORTS; i++) begin
                if (sa_if.in_valid[i] && (sa_if.flit_type[i] == HEAD))
                    is_mcast_reg[i] <= sa_if.is_mcast[i];
            end
        end
    end


    // update register
    // when head flit is granted to the output buffer, the buffer becomes busy
    // and the busy state is released after tail flit is granted
    always_ff @(posedge clk) begin
        if (rst)
            is_obuf_busy_reg <= '0;
        else begin
            for (int k = 0; k < NUM_PORTS; k++) begin
                if (|grant_result[k]) begin
                    if (sa_if.flit_type[grant_id_result[k]] == TAIL)
                        is_obuf_busy_reg[k] <= 1'b0;
                    else
                        is_obuf_busy_reg[k] <= 1'b1;
                end
            end
        end
    end

endmodule
