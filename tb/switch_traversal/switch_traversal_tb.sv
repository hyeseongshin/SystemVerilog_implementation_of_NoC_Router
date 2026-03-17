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

module switch_traversal_tb();
    parameter CLK_PERIOD = 20;
    parameter ROUTER_ID = 9;

    logic clk;

    dest_t  [NUM_PORTS-1:0] tb_mask;

    switch_traversal_if st_if(
        .clk(clk)
    );

    switch_traversal dut (
        .st_if(st_if.st)
    );

    function automatic void generate_mask();
        int pos_col = ROUTER_ID % NUM_COLS;
        int pos_row = ROUTER_ID / NUM_COLS;
        int dst_col;
        int dst_row;

        tb_mask = '0;
        for (int i = 0; i < WIDTH_DEST; i++) begin
            dst_col = i % NUM_COLS;
            dst_row = i / NUM_COLS;
            if ((dst_col == pos_col) && (dst_row == pos_row))
                tb_mask[LOCAL_PORT_NUM][i] = 1'b1;
            else if (dst_col > pos_col)
                tb_mask[EAST_PORT_NUM][i] = 1'b1;
            else if (dst_col < pos_col)
                tb_mask[WEST_PORT_NUM][i] = 1'b1;
            else if (dst_row > pos_row)
                tb_mask[SOUTH_PORT_NUM][i] = 1'b1;
            else if (dst_row < pos_row)
                tb_mask[NORTH_PORT_NUM][i] = 1'b1;
        end
    endfunction

    task automatic monitoring_st();
        flit_t expected_flit;

        forever begin
            @(st_if.monitor_cb);
            for (int k = 0; k < NUM_PORTS; k++) begin
                expected_flit = st_if.monitor_cb.in_flit[st_if.monitor_cb.select_id[k]];
                if (expected_flit.flit_type == HEAD)
                    expected_flit.payload.head_data.dest &= tb_mask;

                if (st_if.monitor_cb.out_flit[k] != expected_flit)
                    $fatal(1, "[Time %0t] TEST FAILED: Wrong ST output", $time);
            end
        end
    endtask

    task automatic drive_sa2st(int iterations);
        flit_t          [NUM_PORTS-1:0] in_flit_tmp;
        port_index_t    [NUM_PORTS-1:0] select_id_tmp;

        for (int i = 0; i < iterations; i++) begin
            @(st_if.driver_cb);
            for (int j = 0; j < NUM_PORTS; j++) begin
                if (!std::randomize(in_flit_tmp[j].flit_type))
                    $fatal(1, "[Time %0t] std::randomize fail", $time);

                in_flit_tmp[j].payload = {$urandom(), $urandom(), $urandom(), $urandom()};
            end
            for (int k = 0; k < NUM_PORTS; k++) begin
                select_id_tmp[k] = port_index_t'($urandom_range(NUM_PORTS - 1, 0));
            end

            st_if.driver_cb.in_flit <= in_flit_tmp;
            st_if.driver_cb.select_id <= select_id_tmp;
        end
    endtask


    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $timeformat(-9, 2, " ns");
        
        generate_mask();
        st_if.mask = tb_mask;
        
        repeat(10) @(negedge clk);

        $display("\n[Time %0t] Inject random inputs", $time);
        fork
            monitoring_st();
            drive_sa2st(100000);
        join_any
        disable fork;

        $display("\n[Time %0t] TEST PASSED", $time);
        $finish();
    end
endmodule