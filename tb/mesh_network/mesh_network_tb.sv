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

// Class that contains packet information.
class message_item;
    int         src_id;
    dest_t      dest;
    int         bytes;
    int         tag;

    function new(int src_id, dest_t dest, int bytes, int tag);
        this.src_id = src_id;
        this.dest = dest;
        this.bytes = bytes;
        this.tag = tag;
    endfunction
endclass


// Class that compares the flits contained in the queues and the flits from each router to pe detected by the monitor
class network_scoreboard;
    message_item expected_messages [NUM_NODES][int];
    int expected_bytes      [NUM_NODES];
    int recieved_bytes      [NUM_NODES];
    int current_tag         [NUM_NODES];
    int valid_bytes         [NUM_NODES];
    int expected_sequence   [NUM_NODES];
    int last_recieved_router;

    function new();
        for (int i = 0; i < NUM_NODES; i++) begin
            expected_bytes[i] = 0;
            recieved_bytes[i] = 0;
            expected_sequence[i] = -1;
        end
    endfunction

    function void add_message(message_item item);
        foreach (item.dest[i]) begin
            if (item.dest[i]) begin
                expected_messages[i][item.tag] = item;
                expected_bytes[i] += item.bytes;
            end
        end
    endfunction

    function void check_flit(int r, int c, flit_t flit);
        int router_id = r * NUM_COLS + c;
        int valid_bytes_tmp;
        int recieved_data;
        int tag;

        if (flit.flit_type == HEAD) begin
            if (expected_sequence[router_id] != -1)
                $fatal(1, "[Time %0t] Scoreboard FATAL: Tail flit was missing. Router %0d, Tag:%0d", $time, router_id, tag);
            valid_bytes_tmp = flit.payload.head_data_pe_view.valid_bytes;
            recieved_data = flit.payload.head_data_pe_view.reserved;
            tag = recieved_data;
        end
        else begin
            recieved_data = flit.payload.data;
            tag = current_tag[router_id];
        end

        if (expected_messages[router_id].exists(tag)) begin
            if (flit.flit_type == HEAD) begin
                current_tag[router_id] = recieved_data;
                valid_bytes[router_id] = valid_bytes_tmp;
                expected_sequence[router_id] = recieved_data + 1;
            end
            else begin
                if (recieved_data != expected_sequence[router_id])
                    $fatal(1, "[Time %0t] Scoreboard FATAL: Flit sequence was corrupted. Router %0d, Tag:%0d, Expected sequence:%0d, Recieved sequence:%0d", $time, router_id, tag, expected_sequence[router_id], recieved_data);
                if (valid_bytes[router_id] <= BYTES_PER_FLIT) begin
                    if (flit.flit_type != TAIL)
                        $fatal(1, "[Time %0t] Scoreboard FATAL: Last flit was not tail flit!", $time);
                    valid_bytes_tmp = valid_bytes[router_id];
                end
                else
                    valid_bytes_tmp = BYTES_PER_FLIT;
                
                recieved_bytes[router_id] += valid_bytes_tmp;
                valid_bytes[router_id] -= valid_bytes_tmp;
                if (flit.flit_type == BODY)
                    expected_sequence[router_id] += 1;
                else begin
                    current_tag[router_id] = -1;
                    expected_sequence[router_id] = -1;
                    last_recieved_router = (r * NUM_COLS + c);
                end
            end
        end
        else begin
            $fatal(1, "[Time %0t] Scoreboard ERROR: Tag mismatch! Router %0d, Tag:%0d", $time, router_id, tag);
        end
    endfunction

    function bit is_all_recieved();
        for (int i = 0; i < NUM_NODES; i++) begin
            if (expected_bytes[i] != recieved_bytes[i]) // Packets do not carry valid data length yet. So, using loose condition
                return 0;
        end
        return 1;
    endfunction
endclass


// class that injects the flits to router as pe
class network_driver;
    virtual mesh_network_if     network_if;
    network_scoreboard          scoreboard;
    mailbox #(message_item)     messages;
    int                         router_id;
    int                         pos_row;
    int                         pos_col;

    function new(virtual mesh_network_if network_if, network_scoreboard scoreboard, mailbox #(message_item) messages, int router_id);
        this.network_if = network_if;
        this.scoreboard = scoreboard;
        this.messages = messages;
        this.router_id = router_id;
        this.pos_row = router_id / NUM_COLS;
        this.pos_col = router_id % NUM_COLS;
    endfunction

    task run();
        message_item    item;
        flit_t          flit;
        int             bytes;
        int             pkt_len;
        int             valid_bytes;

        @(network_if.driver_cb);
        forever begin
            messages.get(item);

            bytes = item.bytes;
            while (bytes > 0) begin
                if (bytes >= (BYTES_PER_FLIT * (MAX_PKT_LEN - 1))) begin
                    pkt_len = MAX_PKT_LEN;
                    valid_bytes = MAX_DATA_BYTES;
                end
                else begin
                    pkt_len = 1 + (bytes + BYTES_PER_FLIT - 1) / BYTES_PER_FLIT;
                    valid_bytes = bytes;
                end

                //head flit
                flit = '0;
                flit.flit_type = HEAD;
                if (item.dest == 0)
                    $fatal(1, "[Time %0t] Driver FATAL: The destination of the message is not set", $time);
                else
                    flit.payload.head_data_pe_view.is_mcast = ($countones(item.dest) >= 2);
                flit.payload.head_data_pe_view.dest = item.dest;
                flit.payload.head_data_pe_view.valid_bytes = valid_bytes;
                flit.payload.head_data_pe_view.reserved = item.tag;

                network_if.driver_cb.pe_out_valid[pos_row][pos_col] <= 1'b1;
                network_if.driver_cb.pe_out_data[pos_row][pos_col] <= flit;
                do begin
                    @(network_if.driver_cb);
                end while(network_if.driver_cb.pe_out_ready[pos_row][pos_col] == 1'b0);
                
                if (!is_network_start) begin
                    network_start_time = $time;
                    is_network_start = 1;
                end

                //body flit
                for (int i = 0; i < (pkt_len - 2); i++) begin
                    flit = '0;
                    flit.flit_type = BODY;
                    flit.payload.data = (item.tag + i + 1);

                    network_if.driver_cb.pe_out_valid[pos_row][pos_col] <= 1'b1;
                    network_if.driver_cb.pe_out_data[pos_row][pos_col] <= flit;
                    do begin
                        @(network_if.driver_cb);
                    end while(network_if.driver_cb.pe_out_ready[pos_row][pos_col] == 1'b0);
                end

                //tail flit
                flit = '0;
                flit.flit_type = TAIL;
                flit.payload.data = item.tag + pkt_len - 1;

                network_if.driver_cb.pe_out_valid[pos_row][pos_col] <= 1'b1;
                network_if.driver_cb.pe_out_data[pos_row][pos_col] <= flit;
                do begin
                    @(network_if.driver_cb);
                end while(network_if.driver_cb.pe_out_ready[pos_row][pos_col] == 1'b0);
                network_if.driver_cb.pe_out_valid[pos_row][pos_col] <= 1'b0;

                bytes -= (pkt_len - 1) * BYTES_PER_FLIT;
            end
        end
    endtask
endclass


// class that detects the flits from router and inform the flits to scoreboard
class network_monitor;
    virtual mesh_network_if network_if;
    network_scoreboard      scoreboard;

    function new(virtual mesh_network_if network_if, network_scoreboard scoreboard);
        this.network_if = network_if;
        this.scoreboard = scoreboard;
    endfunction

    task run();
        forever begin
            @(network_if.monitor_cb);
            for (int r = 0; r < NUM_ROWS; r++) begin
                for (int c = 0; c < NUM_COLS; c++) begin
                    if (network_if.monitor_cb.pe_in_valid[r][c] && network_if.monitor_cb.pe_in_ready[r][c]) begin
                        scoreboard.check_flit(r, c, network_if.monitor_cb.pe_in_data[r][c]);
                        network_end_time = $time;
                    end
                end
            end
        end
    endtask
endclass


// class that logging all output port of each router at every cycle.
class router_logger;
    int fd;
    virtual hybrid_router_if router_if;

    function new(int router_id, virtual hybrid_router_if router_if);
        string file_name = $sformatf("router_%0d.log", router_id);
        fd = $fopen(file_name, "w");
        if (!fd) $fatal(1, "[Time %0t] Logger FATAL: Failed to open log file!", $time);
        $fdisplay(fd, "Time, output_port_L, output_port_N, output_port_E, output_port_S, output_port_W");
        this.router_if = router_if;
    endfunction

    function void close_log();
        if (fd) $fclose(fd);
    endfunction

    task run();
        string log_str;
        time log_time;

        wait(is_network_start == 1);
        forever begin
            if (is_network_start) begin
                log_time = $time - network_start_time;// - CLOCK_PERIOD/2;
                log_str = $sformatf("%0t,\t", log_time);
                for (int k = 0; k < NUM_PORTS; k++) begin
                    if (router_if.monitor_cb.out_valid[k] && router_if.monitor_cb.out_ready[k])
                        log_str = {log_str, $sformatf("%s,\t", router_if.monitor_cb.out_data[k].flit_type.name())};
                    else
                        log_str = {log_str, "-,\t"};
                end
                $fdisplay(fd, "%s", log_str);
            end
            @(router_if.monitor_cb);
        end
    endtask
endclass


class network_env;
    virtual mesh_network_if     network_if;
    network_scoreboard          scoreboard;
    network_monitor             monitor;
    network_driver              driver      [NUM_NODES];
    mailbox #(message_item)     messages    [NUM_NODES];
    router_logger               loggers     [NUM_NODES];

    function new(virtual mesh_network_if network_if, virtual hybrid_router_if router_ifs[NUM_NODES]);
        this.network_if = network_if;
        this.scoreboard = new();
        this.monitor = new(network_if, scoreboard);
        for (int i = 0; i < NUM_NODES; i++) begin
            this.messages[i] = new();
            this.driver[i] = new(network_if, this.scoreboard, this.messages[i], i);
            this.loggers[i] = new(i, router_ifs[i]);
        end
    endfunction

    task configure_mesh_network(int router_id);
        int pos_row = router_id / NUM_COLS;
        int pos_col = router_id % NUM_COLS;
        int dst_row;
        int dst_col;
        port_mask_t [NUM_ROWS-1:0][NUM_COLS-1:0] cfg_data_tmp;

        @(network_if.driver_cb);
        for (int i = 0; i < WIDTH_DEST; i++) begin
            dst_col = i % NUM_COLS;
            dst_row = i / NUM_COLS;
            cfg_data_tmp = '0;
            if ((dst_col == pos_col) && (dst_row == pos_row)) 
                cfg_data_tmp |= (port_mask_t'(1) << LOCAL_PORT_NUM);
            else if (dst_col > pos_col)
                cfg_data_tmp |= (port_mask_t'(1) << EAST_PORT_NUM);
            else if (dst_col < pos_col)
                cfg_data_tmp |= (port_mask_t'(1) << WEST_PORT_NUM);
            else if (dst_row > pos_row)
                cfg_data_tmp |= (port_mask_t'(1) << SOUTH_PORT_NUM);
            else if (dst_row < pos_row)
                cfg_data_tmp |= (port_mask_t'(1) << NORTH_PORT_NUM);

            network_if.driver_cb.cfg_valid[pos_row][pos_col] <= 1'b1;
            network_if.driver_cb.cfg_data[pos_row][pos_col] <= cfg_data_tmp;
            do begin
                @(network_if.driver_cb);
            end while(network_if.driver_cb.cfg_ready[pos_row][pos_col] == 1'b0);
        end
        network_if.driver_cb.cfg_valid <= 1'b0;

        @(network_if.driver_cb);
        if (network_if.driver_cb.cfg_ready[pos_row][pos_col] != 1'b0) begin
            global_error_cnt++;
            $error("[Time %0t] Env ERROR: Router %d configuration did not end!", $time, router_id);
        end
    endtask

    task load_scenario();
        int fd;
        int code;
        int src_id;
        int bytes;
        int tag_cnt = 1;
        dest_t dest;
        message_item item;

        fd = $fopen("scenario_0.txt", "r");
        if (!fd) $fatal(1, "[Time %0t]Env FATAL: Failed to open scenario file!", $time);
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%d %h %d\n", src_id, dest, bytes);
            if (code == 3) begin
                item = new(src_id, dest, bytes, tag_cnt++);
                scoreboard.add_message(item);
                messages[src_id].put(item);
            end
            else if (code == -1) 
                break;
            else
                $fgetc(fd);
        end
        $fclose(fd);
        $display("[Time %0t] Env: Scenario file parsing completed. total %0d messages loaded!", $time, (tag_cnt - 1));
    endtask
    
    task run();
        dest_t dest;
        int output_port;
        $display("Load scenario");
        load_scenario();

        $display("Configure network");
        for (int i = 0; i < NUM_NODES; i++) begin
            automatic int router_id = i;
            fork
            configure_mesh_network(router_id);
            join_none
        end
        wait fork;

        $display("Simulation Start");
        fork
            monitor.run();
        join_none
        for (int i = 0; i < NUM_NODES; i++) begin
            automatic int router_id = i;
            fork
                loggers[router_id].run();
                driver[router_id].run();
            join_none
        end

        fork
            begin
                forever begin
                    @(network_if.monitor_cb);
                    if (scoreboard.is_all_recieved())
                        break;
                end
            end
            begin
                repeat(100000) @(network_if.monitor_cb);
                $display("Simulation Timeout!");
                for (int i = 0; i < NUM_NODES; i++) begin
                    $display("- Router %0d: Exp %0d / Recv %0d", i, scoreboard.expected_bytes[i], scoreboard.recieved_bytes[i]);
                end
                $display("TEST FAILED");
            end
        join_any
        disable fork;

        $display("\n=========================");
        $display("Simulation End");
        for (int i = 0; i < NUM_NODES; i++) begin
            $display("- Router %0d: Exp %0d / Recv %0d", i, scoreboard.expected_bytes[i], scoreboard.recieved_bytes[i]);
            loggers[i].close_log();
        end
        $display("Total Errors: %0d", global_error_cnt);
        if (global_error_cnt == 0) begin
            $display("TEST PASSED");
            $display("Last router : %0d", scoreboard.last_recieved_router);
            $display("Start time : %0d ns", network_start_time);
            $display("End time : %0d ns", network_end_time);
            $display("Total time : %0d ns", network_end_time - network_start_time);
        end
        else
            $display("TEST FAILED");
        $display("\n=========================");
        $finish();
    endtask
endclass


module mesh_network_tb();
    logic clk;
    logic rst;

    mesh_network_if network_if(
        .clk(clk)
    );

    mesh_network dut (
        .clk(clk),
        .rst(rst),
        .network_if(network_if)
    );

    bind hybrid_router route_computation_sva rc_sva (
        .clk(clk),
        .rst(rst),
        .rc_if(rc_if),
        .is_mcast(ireg_is_mcast)
    );

    bind switch_allocation switch_allocation_sva sa_sva (
        .clk(clk),
        .rst(rst),
        .sa_if(sa_if),
        .is_obuf_busy_reg(is_obuf_busy_reg)
    );

    bind round_robin_arbiter round_robin_arbiter_sva #(.NUM_REQS(NUM_PORTS)) rr_arb_sva (
        .clk(clk),
        .rst(rst),
        .grant(grant)
    );

    virtual hybrid_router_if router_ifs[NUM_NODES];
    for (genvar r = 0; r < NUM_ROWS; r++) begin : gen_row_bind
        for (genvar c = 0; c < NUM_COLS; c++) begin : gen_col_bind
            initial begin
                router_ifs[r * NUM_COLS + c] = dut.gen_row[r].gen_col[c].router_if;
            end
        end
    end

    network_env env;

    initial begin
        clk = 1'b0;
        forever begin
            #(CLOCK_PERIOD/2) clk = ~clk;
        end
    end

    initial begin
        $timeformat(-9, 2, " ns");

        rst = 1'b1;
        network_if.cfg_valid = '0;
        network_if.pe_out_valid = '0;
        network_if.pe_in_ready = '1;

        repeat(100) @(negedge clk);
        rst = 1'b0;

        env = new(network_if, router_ifs);
        env.run();
    end

endmodule