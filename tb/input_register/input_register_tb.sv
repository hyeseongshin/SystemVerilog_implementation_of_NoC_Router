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

module input_register_tb;
    parameter CLK_PERIOD = 20;
    
    logic clk;
    logic rst;

    int random_interations;
    int random_data;

    flit_t expected_datas[$];

    input_register_if ireg_if(
        .clk(clk)
    );

    input_register dut (
        .clk(clk),
        .rst(rst),
        .ireg_if(ireg_if.ireg)
    );

    task automatic drive_network2ireg(int iters);
        int random_data;

        @(ireg_if.driver_cb);
        for (int i = 0; i < iters; i++) begin
            random_data = $urandom();
            expected_datas.push_back(flit_t'(random_data));

            ireg_if.driver_cb.in_valid <= 1'b1;
            ireg_if.driver_cb.in_data <= flit_t'(random_data);

            do begin
                @(ireg_if.driver_cb);
            end while(ireg_if.in_ready == 0);
        end
        ireg_if.driver_cb.in_valid <= 1'b0;
    endtask

    task automatic drive_sa2ireg(bit has_back_pressure);
        @(ireg_if.driver_cb);
        forever begin
            if (has_back_pressure) begin
                ireg_if.driver_cb.out_ready <= 1'b0;
                repeat($urandom_range(100, 10)) @(ireg_if.driver_cb);
                ireg_if.driver_cb.out_ready <= 1'b1;
            end
            else
                ireg_if.driver_cb.out_ready <= 1'b1;

            do begin
                @(ireg_if.driver_cb);
            end while(ireg_if.driver_cb.out_valid == 1'b0);
        end
    endtask

    task automatic monitoring_ireg();
        flit_t expected_data;

        forever begin
            @(ireg_if.monitor_cb);
            if (ireg_if.monitor_cb.out_valid && ireg_if.monitor_cb.out_ready) begin
                if (expected_datas.size() > 0)
                    expected_data = expected_datas.pop_front();
                else
                    $fatal(1, "[Time %0t] TEST FAILED: Queue is empty but output is valid", $time);

                if (ireg_if.monitor_cb.out_data != expected_data)
                    $fatal(1, "[Time %0t] TEST FAILED: Input data and output data is not same", $time);
            end

        end
    endtask

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    initial begin
        $timeformat(-9, 2, " ns");

        rst = 1'b1;
        ireg_if.in_valid = '0;
        ireg_if.in_data = '0;
        ireg_if.out_ready = '1;

        repeat(100) @(negedge clk);
        rst = 1'b0;

        $display("\n[Time %0t] Injects random datas without back pressure", $time);
        fork
            monitoring_ireg();
            drive_sa2ireg(0);
            begin
                drive_network2ireg(10000);
                wait(expected_datas.size() == 0);
            end
        join_any
        disable fork;

        $display("\n[Time %0t] Injects random datas with back pressure", $time);
        fork
            monitoring_ireg();
            drive_sa2ireg(1);
            begin
                drive_network2ireg(10000);
                wait(expected_datas.size() == 0);
            end
        join_any
        disable fork;

        $display("\n[Time %0t] TEST PASSED", $time);
        $finish();
    end

endmodule