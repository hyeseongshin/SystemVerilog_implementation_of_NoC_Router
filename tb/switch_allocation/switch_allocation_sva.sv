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
import setting_tb::*;

module switch_allocation_sva
(
    input logic                         clk,
    input logic                         rst,

    switch_allocation_if                sa_if,
    input is_mcast_t    [NUM_PORTS-1:0] is_mcast_reg,
    input logic         [NUM_PORTS-1:0] is_obuf_busy_reg
);

    for (genvar k = 0; k < NUM_PORTS; k++) begin : gen_sva
        property p_grant_needs_request();
            @(posedge clk) disable iff (rst)
            (sa_if.grant[k] != 0) |-> ((sa_if.in_valid[sa_if.grant_id[k]] == 1'b1) && (sa_if.request[sa_if.grant_id[k]][k] == 1'b1));
        endproperty

        property p_grant_onehot();
            @(posedge clk) disable iff (rst)
            (sa_if.grant[k] != 0) |-> $onehot(sa_if.grant[k]);
        endproperty

        property p_grant_id_match();
            @(posedge clk) disable iff (rst)
            (sa_if.grant[k] != 0) |-> (sa_if.grant_id[k] == $clog2(sa_if.grant[k]));
        endproperty


        // unicast packet follows wormhole
        // for head flit, it needs buffer occupancy and available space for a flit
        property p_wormhole_unicast_head();
            @(posedge clk) disable iff (rst)
            ((sa_if.grant[k] != 0)
                && (sa_if.is_mcast[sa_if.grant_id[k]] != 1'b1)
                && (sa_if.flit_type[sa_if.grant_id[k]] == HEAD))
                    |-> ((sa_if.in_valid[sa_if.grant_id[k]] == 1'b1)
                            && (is_obuf_busy_reg[k] != 1'b1)
                            && (sa_if.obuf_num_free[k] >= 1));
        endproperty

        // for body and tail flit, it checks available space for a flit
        // and check output buffer occupancy since this packet have occupancy
        property p_wormhole_unicast_body_tail();
            @(posedge clk) disable iff (rst)
            ((sa_if.grant[k] != 0) 
                && (is_mcast_reg[sa_if.grant_id[k]] != 1'b1)
                && (sa_if.flit_type[sa_if.grant_id[k]] != HEAD)) 
                    |-> ((sa_if.in_valid[sa_if.grant_id[k]] == 1'b1)
                            && (is_obuf_busy_reg[k] == 1'b1)
                            && (sa_if.obuf_num_free[k] >= 1));
        endproperty


        // multicast packet follows cut-through
        // for head flit, it needs buffer occupancy and available space for a packet
        property p_cut_through_multicast_head();
            @(posedge clk) disable iff (rst)
            ((sa_if.grant[k] != 0)
                && (sa_if.is_mcast[sa_if.grant_id[k]] == 1'b1)
                && (sa_if.flit_type[sa_if.grant_id[k]] == HEAD))
                    |-> ((sa_if.in_valid[sa_if.grant_id[k]] == 1'b1)
                            && (is_obuf_busy_reg[k] != 1'b1)
                            && (sa_if.obuf_num_free[k] >= MAX_PKT_LEN));
        endproperty

        // for body or tail flit, bypass further checks as cut-through conditions already checked by head flit
        // but check output buffer occupancy since this packet have occupancy
        property p_cut_through_multicast_body_tail();
            @(posedge clk) disable iff (rst)
            ((sa_if.grant[k] != 0)
                && (is_mcast_reg[sa_if.grant_id[k]] == 1'b1)
                && (sa_if.flit_type[sa_if.grant_id[k]] != HEAD))
                    |-> ((sa_if.in_valid[sa_if.grant_id[k]] == 1'b1)
                            && (is_obuf_busy_reg[k] == 1'b1));
        endproperty


        a_wormhole_unicast_head:
        assert property (p_wormhole_unicast_head())
            else begin
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: A unicast packet (head flit) from port %0d violates wormhole condition", $time, sa_if.grant_id[k]);
            end

        a_wormhole_unicast_body_tail:
        assert property (p_wormhole_unicast_body_tail())
            else begin
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: A unicast packet (body/tail flit) from port %0d violates wormhole condition", $time, sa_if.grant_id[k]);
            end

        a_cut_through_multicast_head:
        assert property (p_cut_through_multicast_head())
            else begin
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: A multicast packet (head flit) from port %0d violates cut-through condition", $time, sa_if.grant_id[k]);
            end

        a_cut_through_multicast_body_tail:
        assert property (p_cut_through_multicast_body_tail())
            else begin
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: A multicast packet (body/tail flit) from port %0d violates cut-through condition", $time, sa_if.grant_id[k]);
            end

        a_grant_needs_request:
        assert property (p_grant_needs_request())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: Obuf %0d granted an input without a valid request", $time, k);
            end

        a_grant_onehot:
        assert property (p_grant_onehot())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: Obuf %0d granted multiple inputs simultaneously", $time, k);
            end

        a_grant_id_match:
        assert property (p_grant_id_match())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] SA ERROR: Grant index %0d do not match with grant vector", $time, k);
            end
    end

endmodule