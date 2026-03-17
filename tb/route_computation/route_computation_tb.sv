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
 

`timescale 1ns / 1ps

import setting_noc::*;
import setting_tb::*;

module route_computation_tb();
    parameter CLK_PERIOD = 20;
    parameter ROUTER_ID = 9;

    logic clk;
    logic rst;

    is_mcast_t  [NUM_PORTS-1:0]     ireg_is_mcast;
    port_mask_t [WIDTH_DEST-1:0]    golden_LUT;
    dest_t      [NUM_PORTS-1:0]     golden_mask;

    route_computation_if rc_if(
        .clk(clk)
    );

    route_computation dut (
        .clk(clk),
        .rst(rst),
        .rc_if(rc_if.rc)
    );
    
    bind route_computation route_computation_sva rc_sva (
        .clk(clk),
        .rst(rst),
        .rc_if(rc_if),
        .is_mcast(route_computation_tb.ireg_is_mcast)
    );

    function automatic port_mask_t get_target_ports(dest_t dest);
        int pos_col = ROUTER_ID % NUM_COLS;
        int pos_row = ROUTER_ID / NUM_COLS;
        int dst_col;
        int dst_row;
        port_mask_t target_ports;

        target_ports = '0;
        foreach (dest[i]) begin
            if (dest[i]) begin
                dst_col = i % NUM_COLS;
                dst_row = i / NUM_COLS;
                if ((dst_col == pos_col) && (dst_row == pos_row))
                    target_ports |= (port_mask_t'(1) << LOCAL_PORT_NUM);
                else if (dst_col > pos_col)
                    target_ports |= (port_mask_t'(1) << EAST_PORT_NUM);
                else if (dst_col < pos_col)
                    target_ports |= (port_mask_t'(1) << WEST_PORT_NUM);
                else if (dst_row > pos_row)
                    target_ports |= (port_mask_t'(1) << SOUTH_PORT_NUM);
                else if (dst_row < pos_row)
                    target_ports |= (port_mask_t'(1) << NORTH_PORT_NUM);
            end
        end
        return target_ports;
    endfunction

    function automatic dest_t correct_dest(int input_port, dest_t dest);
        int pos_col = ROUTER_ID % NUM_COLS;
        int pos_row = ROUTER_ID / NUM_COLS;
        int dst_col;
        int dst_row;

        for (int k = 0; k < WIDTH_DEST; k++) begin
            if (dest[k]) begin
                dst_col = k % NUM_COLS;
                dst_row = k / NUM_COLS;
                case (input_port) // remove U-turn & Y-axis First case
                    LOCAL_PORT_NUM: begin
                        if (k == ROUTER_ID)
                            dest[k] = 1'b0;
                    end
                    NORTH_PORT_NUM: begin
                        if ((dst_col != pos_col) || (dst_row < pos_row))
                            dest[k] = 1'b0;
                    end
                    EAST_PORT_NUM:  begin
                        if (dst_col > pos_col)
                            dest[k] = 1'b0;
                    end
                    SOUTH_PORT_NUM: begin
                        if ((dst_col != pos_col) || (dst_row > pos_row))
                            dest[k] = 1'b0;
                    end
                    WEST_PORT_NUM:  begin
                        if (dst_col < pos_col)
                            dest[k] = 1'b0;
                    end
                    default: $fatal(1, "[Time %0t] TEST FAILED: Wrong input port (Port:%0d)", $time, input_port);
                endcase
            end
        end
        return dest;
    endfunction

    task configure_rc();
        @(rc_if.driver_cb);
        for (int i = 0; i < WIDTH_DEST; i++) begin
            rc_if.driver_cb.cfg_valid <= 1'b1;
            golden_LUT[i] = get_target_ports(dest_t'(1) << i);
            rc_if.driver_cb.cfg_data <= golden_LUT[i];
            do begin
                @(rc_if.driver_cb);
            end while (rc_if.driver_cb.cfg_ready == 1'b0);

            if ($urandom_range(100, 1) <= 10) begin
                rc_if.driver_cb.cfg_valid <= 1'b0;
                repeat($urandom_range(10, 1)) @(rc_if.driver_cb);
            end
        end
        rc_if.driver_cb.cfg_valid <= 1'b0;

        @(rc_if.driver_cb);
        if (rc_if.driver_cb.cfg_ready != 1'b0) begin
            global_error_cnt++;
            $fatal(1, "[Time %0t] Env ERROR: Router configuration did not end!", $time);
        end
        
        foreach (golden_LUT[i, k]) begin
            golden_mask[k][i] = golden_LUT[i][k];
        end
    endtask

    task automatic monitor_rc();
        port_mask_t expected_request;

        forever begin
            @(rc_if.monitor_cb);
            for (int i = 0; i < NUM_PORTS; i++) begin
                if (rc_if.monitor_cb.in_valid[i] && (rc_if.monitor_cb.request[i] != expected_request)) begin
                    expected_request = get_target_ports(rc_if.monitor_cb.request[i]);
                    $fatal(1, "[Time %0t] TEST FAILED: Wrong RC output with %d flit! (Port:%0d) expected %b", $time, i, rc_if.monitor_cb.flit_type[i].name(), expected_request);
                end
            end
        end
    endtask

    task automatic drive_rc(int input_port, int iterations);
        bit in_valid_tmp;
        port_mask_t expected_request;
        int random_pkt_len;
        dest_t dest_tmp;
        int is_ucast;
        int dest_cnt;
        int dest_list[];
        int all_nodes[] = new[NUM_NODES];
        foreach (all_nodes[node])
            all_nodes[node] = node;

        for (int i = 0; i < iterations; i++) begin
            @(rc_if.driver_cb);
            dest_tmp = '0;
            is_ucast = ($urandom_range(100, 1) <= 80);
            if (is_ucast) begin
                dest_list = new[1];
                dest_list[0] = $urandom_range(NUM_NODES-1, 0);
            end
            else begin
                all_nodes.shuffle();
                dest_cnt = $urandom_range(NUM_NODES, 2);
                dest_list = new[dest_cnt];
                foreach (dest_list[j])
                    dest_list[j] = all_nodes[j];
            end
            foreach (dest_list[node])
                dest_tmp[dest_list[node]] = 1'b1;

            dest_tmp = correct_dest(input_port, dest_tmp);
            ireg_is_mcast[input_port] = ($countones(dest_tmp) >= 2);
            in_valid_tmp = (dest_tmp != 0);

            rc_if.driver_cb.flit_type[input_port] <= HEAD;
            rc_if.driver_cb.in_valid[input_port] <= in_valid_tmp;
            rc_if.driver_cb.dest[input_port] <= dest_tmp;

            random_pkt_len = $urandom_range(MAX_PKT_LEN - 2, 1);
            for (int k = 0; k < random_pkt_len; k++) begin
                @(rc_if.driver_cb);
                rc_if.driver_cb.flit_type[input_port] <= BODY;
                rc_if.driver_cb.dest[input_port] <= '0;
            end

            @(rc_if.driver_cb);
            rc_if.driver_cb.flit_type[input_port] <= TAIL;
            rc_if.driver_cb.dest[input_port] <= '0;
        end
        @(rc_if.driver_cb);
        rc_if.driver_cb.in_valid[input_port] <= 1'b0;
    endtask


    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $timeformat(-9, 2, " ns");

        rst = 1'b1;
        rc_if.cfg_valid = '0;
        rc_if.in_valid = '0;
        
        repeat(10) @(negedge clk);
        rst = 1'b0;

        repeat(10) @(negedge clk);
        configure_rc();
        repeat(10) @(negedge clk);
        $display("\n[Time %0t] Test RC mask", $time);
        if (rc_if.mask != golden_mask)
            $fatal(1, "[Time %0t] TEST FAILED: Wrong mask", $time);

        $display("\n[Time %0t] Inject random dests", $time);

        fork
            monitor_rc();
            begin
                for (int i = 0; i < NUM_PORTS; i++) begin
                    automatic int port_idx = i;
                    fork
                        drive_rc(port_idx, 100000);
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