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
 

`timescale 1ns / 1ps

import setting_noc::*;
import setting_tb::*;

module switch_allocation_tb();
    parameter CLK_PERIOD = 20;

    logic clk;
    logic rst;

    logic           [NUM_PORTS-1:0] tb_is_mcast_reg;
    logic           [NUM_PORTS-1:0] tb_is_obuf_busy_reg;
    obuf_depth_t    [NUM_PORTS-1:0] tb_obuf_num_free;
    port_index_t    [NUM_PORTS-1:0] tb_last_grant_id_ucast;

    port_mask_t     [NUM_PORTS-1:0] expected_grant;
    port_index_t    [NUM_PORTS-1:0] expected_grant_id;


    switch_allocation_if sa_if(
        .clk(clk)
    );

    switch_allocation dut (
        .clk(clk),
        .rst(rst),
        .sa_if(sa_if.sa)
    );
    
    bind switch_allocation switch_allocation_sva sa_sva (
        .clk(clk),
        .rst(rst),
        .sa_if(sa_if),
        .is_mcast_reg(is_mcast_reg),
        .is_obuf_busy_reg(is_obuf_busy_reg)
    );

    bind round_robin_arbiter round_robin_arbiter_sva rr_arb_sva (
        .clk(clk),
        .rst(rst),
        .grant(grant)
    );

    function automatic port_mask_t correct_request(int input_port, port_mask_t request);
        for (int k = 0; k < NUM_PORTS; k++) begin
            if (request[k]) begin
                case (input_port) // remove U-turn & Y-axis First case
                    LOCAL_PORT_NUM: begin
                        if (k == LOCAL_PORT_NUM)
                            request[k] = 1'b0;
                    end
                    NORTH_PORT_NUM: begin
                        if ((k == NORTH_PORT_NUM) || (k == EAST_PORT_NUM) || (k == WEST_PORT_NUM))
                            request[k] = 1'b0;
                    end
                    EAST_PORT_NUM:  begin
                        if (k == EAST_PORT_NUM)
                            request[k] = 1'b0;
                    end
                    SOUTH_PORT_NUM: begin
                        if ((k == SOUTH_PORT_NUM) || (k == EAST_PORT_NUM) || (k == WEST_PORT_NUM))
                            request[k] = 1'b0;
                    end
                    WEST_PORT_NUM:  begin
                        if (k == WEST_PORT_NUM)
                            request[k] = 1'b0;
                    end
                    default: $fatal(1, "[Time %0t] TEST FAILED: Wrong input port", $time);
                endcase
            end
        end
        return request;
    endfunction

    function automatic port_mask_t [NUM_PORTS-1:0] transpose(port_mask_t [NUM_PORTS-1:0] grant);
        port_mask_t [NUM_PORTS-1:0] grant_transposed;
        foreach (grant[k, i])
            grant_transposed[i][k] = grant[k][i];
        return grant_transposed;
    endfunction

    function automatic void sa_behavior();
        is_mcast_t  [NUM_PORTS-1:0] is_mcast_pkt;
        port_mask_t [NUM_PORTS-1:0] valid_ucast;
        port_mask_t [NUM_PORTS-1:0] valid_mcast;

        expected_grant = '0;
        expected_grant_id = '0;

        //request -> valid
        for (int i = 0; i < NUM_PORTS; i++) begin
            valid_mcast[i] = '0;
            valid_ucast[i] = '0;

            if (sa_if.monitor_cb.in_valid[i]) begin
                if (sa_if.monitor_cb.flit_type[i] == HEAD)
                    is_mcast_pkt[i] = sa_if.monitor_cb.is_mcast[i];
                else
                    is_mcast_pkt[i] = tb_is_mcast_reg[i];

                if (is_mcast_pkt[i]) begin
                    for (int k = 0; k < NUM_PORTS; k++) begin
                        if (sa_if.monitor_cb.request[i][k]) begin
                            if (sa_if.monitor_cb.flit_type[i] == HEAD) begin
                                if (!tb_is_obuf_busy_reg[k] && (sa_if.monitor_cb.obuf_num_free[k] >= MAX_PKT_LEN))
                                    valid_mcast[i][k] = 1'b1;
                            end
                            else
                                valid_mcast[i][k] = 1'b1;
                        end
                    end
                    if (sa_if.monitor_cb.request[i] != valid_mcast[i])
                        valid_mcast[i] = '0;
                end
                else begin
                    for (int k = 0; k < NUM_PORTS; k++) begin
                        if (sa_if.monitor_cb.request[i][k]) begin
                            if (sa_if.monitor_cb.obuf_num_free[k] >= 1) begin
                                if (sa_if.monitor_cb.flit_type[i] == HEAD) begin
                                    if (!tb_is_obuf_busy_reg[k])
                                        valid_ucast[i][k] = 1'b1;
                                end
                                else
                                    valid_ucast[i][k] = 1'b1;
                            end
                            break;
                        end
                    end
                end
            end
        end

        //valid -> grant (multicast first, fixed priority)
        for (int i = 0; i < NUM_PORTS; i++) begin
            if (valid_mcast[i] != 0) begin
                for (int k = 0; k < NUM_PORTS; k++)
                    expected_grant[k][i] = valid_mcast[i][k];

                for (int j = i + 1; j < NUM_PORTS; j++)
                    for (int k = 0; k < NUM_PORTS; k++)
                        if (expected_grant[k] != 0)
                            if (valid_mcast[j][k])
                                valid_mcast[j] = '0;
            end
        end

        //valid -> grant (unicast last, round robin)
        for (int k = 0; k < NUM_PORTS; k++) begin
            if (expected_grant[k] == 0) begin
                for (int i = 1; i <= NUM_PORTS; i++) begin
                    int idx = (tb_last_grant_id_ucast[k] + i) % NUM_PORTS;
                    if (valid_ucast[idx][k]) begin
                        expected_grant[k][idx] = 1'b1;
                        tb_last_grant_id_ucast[k] = port_index_t'(idx);
                        break;
                    end
                end
            end
        end

        //grant -> grant_id
        foreach (expected_grant[k])
            if (expected_grant[k] != 0)
                expected_grant_id[k] = port_index_t'($clog2(expected_grant[k]));

        //update tb_is_mcast_reg, tb_is_obuf_busy_reg
        for (int i = 0; i < NUM_PORTS; i++)
            if (sa_if.monitor_cb.in_valid[i])
                if (sa_if.monitor_cb.flit_type[i] == HEAD)
                    tb_is_mcast_reg[i] = sa_if.monitor_cb.is_mcast[i];
        
        for (int k = 0; k < NUM_PORTS; k++) begin
            if (expected_grant[k] != 0) begin
                tb_is_obuf_busy_reg[k] = 1'b1;
                if (sa_if.monitor_cb.flit_type[expected_grant_id[k]] == TAIL)
                    tb_is_obuf_busy_reg[k] = 1'b0;
            end
        end
    endfunction
    
    task automatic monitoring_sa();
        tb_is_mcast_reg = '0;
        tb_is_obuf_busy_reg = '0;
        for (int k = 0; k < NUM_PORTS; k++)
            tb_last_grant_id_ucast[k] = port_index_t'(NUM_PORTS - 1);

        forever begin
            @(sa_if.monitor_cb);
            sa_behavior();

            if (sa_if.monitor_cb.grant != expected_grant)
                $fatal(1, "[Time %0t] TEST FAILED: Wrong SA output grant.", $time);

            if (sa_if.monitor_cb.grant_id != expected_grant_id)
                $fatal(1, "[Time %0t] TEST FAILED: Wrong SA output grant_id.", $time);
        end
    endtask

    task automatic drive_obuf2sa();
        tb_is_mcast_reg = '0;
        tb_is_obuf_busy_reg = '0;
        for (int k = 0; k < NUM_PORTS; k++)
            tb_obuf_num_free[k] = obuf_depth_t'(MAX_PKT_LEN);

        forever begin
            @(sa_if.monitor_cb);
            foreach (tb_obuf_num_free[k]) begin
                if (sa_if.monitor_cb.grant[k] != 0)
                    tb_obuf_num_free[k]--;

                if ((tb_obuf_num_free[k] < MAX_PKT_LEN) && ($urandom_range(100, 1) >= 50))
                    tb_obuf_num_free[k]++;
            end

            sa_if.driver_cb.obuf_num_free <= tb_obuf_num_free;
        end
    endtask

    task automatic drive_ibuf_and_rc2sa(int input_port, int iterations);
        bit in_valid_tmp;
        port_mask_t request_tmp;
        int random_pkt_len;
        port_mask_t grant_transposed;

        @(sa_if.driver_cb);
        for (int i = 0; i < iterations; i++) begin
            request_tmp = port_mask_t'($urandom_range(((1 << $bits(port_mask_t)) - 1), 0));
            request_tmp = correct_request(input_port, request_tmp);
            in_valid_tmp = (request_tmp != 0);

            sa_if.driver_cb.flit_type[input_port] <= HEAD;
            sa_if.driver_cb.in_valid[input_port] <= in_valid_tmp;
            sa_if.driver_cb.is_mcast[input_port] <= is_mcast_t'($countones(request_tmp) >= 2);
            sa_if.driver_cb.request[input_port] <= request_tmp;
            if (in_valid_tmp) begin
                do begin
                    @(sa_if.driver_cb);
                end while(transpose(sa_if.driver_cb.grant)[input_port] == 0);
            end
            else begin
                @(sa_if.driver_cb);
                continue;
            end

            random_pkt_len = $urandom_range(MAX_PKT_LEN - 2, 1);
            for (int k = 0; k < random_pkt_len; k++) begin
                sa_if.driver_cb.flit_type[input_port] <= BODY;
                do begin
                    @(sa_if.driver_cb);
                end while(transpose(sa_if.driver_cb.grant)[input_port] == 0);
            end

            sa_if.driver_cb.flit_type[input_port] <= TAIL;
            do begin
                @(sa_if.driver_cb);
            end while(transpose(sa_if.driver_cb.grant)[input_port] == 0);
        end
        sa_if.driver_cb.in_valid[input_port] <= 1'b0;
    endtask


    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $timeformat(-9, 2, " ns");
        
        rst = 1'b1;
        sa_if.in_valid = '0;
        
        repeat(10) @(negedge clk);
        rst = 1'b0;

        $display("\n[Time %0t] Inject random requests", $time);
        fork
            monitoring_sa();
            drive_obuf2sa();
            begin
                for (int i = 0; i < NUM_PORTS; i++) begin
                    automatic int port_idx = i;
                    fork
                        drive_ibuf_and_rc2sa(port_idx, 100000);
                    join_none
                end
                wait fork;
            end
        join_any
        disable fork;

        if(global_error_cnt > 0)
            $fatal(1, "[Time %0t] TEST FAILED: Check SVA", $time);
        $display("\n[Time %0t] TEST PASSED", $time);
        $finish();
    end
endmodule