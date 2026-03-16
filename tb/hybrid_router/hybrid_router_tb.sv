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

// Class that contains packet information.
class packet_item;
    dest_t      dest;
    port_mask_t target_ports;
    int         pkt_len;
    int         tag;

    function new(int router_id, dest_t dest, port_mask_t target_ports, int pkt_len, int tag);
        this.dest = dest;
        this.target_ports = target_ports;
        this.pkt_len = pkt_len;
        this.tag = tag;
    endfunction
endclass


// Class that compares the flits contained in the queues and the flits from router detected by the monitor
class router_scoreboard;
    typedef struct {
        int input_port;
        flit_t flit;
    } flit_w_input_port;

    flit_w_input_port flit_queue [NUM_PORTS][int][$];

    int send_cnt = 0;
    int match_cnt = 0;
    int mismatch_cnt = 0;

    function void add_flit(port_mask_t port_mask, int tag, int input_port, flit_t flit);
        flit_w_input_port wrapped_flit;

        foreach (port_mask[i]) begin
            if (port_mask[i]) begin
                wrapped_flit.input_port = input_port;
                wrapped_flit.flit = flit;

                flit_queue[i][tag].push_back(wrapped_flit);
                send_cnt++;
            end
        end
    endfunction

    function void check_flit(int port_idx, flit_t actual_flit);
        int actual_tag;
        int expected_tag;
        flit_w_input_port expected_flit;

        if (actual_flit.flit_type == HEAD)
            actual_tag = actual_flit.payload.head_data.reserved;
        else
            actual_tag = actual_flit.payload.data;

        if (flit_queue[port_idx].exists(actual_tag) && (flit_queue[port_idx][actual_tag].size() > 0)) begin
            expected_flit = flit_queue[port_idx][actual_tag].pop_front();
            if (expected_flit.flit.flit_type == HEAD)
                expected_tag = expected_flit.flit.payload.head_data.reserved;
            else
                expected_tag = expected_flit.flit.payload.data;

            if (expected_tag == actual_tag) begin                
                //$display("[Time %0t] Scoreboard PASS: Tag match! Output port %0d, Tag:%0d (Input port:%0d, Type:%0s)", $time, port_idx, expected_tag, expected_flit.input_port, expected_flit.flit.flit_type.name());
                match_cnt++;
            end
            else begin
                //$display("[Time %0t] Scoreboard ERROR: Tag mismatch! Output port %0d, Tag:%0d", $time, port_idx, actual_tag);
                mismatch_cnt++;
            end
        end
        else begin
            //$display("[Time %0t] Scoreboard ERROR: Unexpected packet! Output port %0d, Tag:%0d", $time, port_idx, actual_tag);
            mismatch_cnt++;
        end
    endfunction
endclass


// class that injects the flits to each port of router and records the input flits to the scoreboard
class router_driver;
    virtual hybrid_router_if    router_if;
    router_scoreboard           scoreboard;
    mailbox #(packet_item)      messages;
    int                         router_id;
    int                         input_port;

    function new(virtual hybrid_router_if router_if, router_scoreboard scoreboard, mailbox #(packet_item) messages, int router_id, int input_port);
        this.router_if = router_if;
        this.scoreboard = scoreboard;
        this.messages = messages;
        this.router_id = router_id;
        this.input_port = input_port;
    endfunction

    task run();
        packet_item             item;
        flit_t                  flit;

        router_if.driver_cb.in_valid[input_port] <= 1'b0;
        @(router_if.driver_cb);
        forever begin
            messages.get(item);

            //head flit
            flit = '0;
            flit.flit_type = HEAD;
            if (item.dest == 0)
                $fatal(1, "[Time %0t] Driver FATAL: The destination of the packet is not set", $time);
            else
                flit.payload.head_data.is_mcast = ($countones(item.dest) >= 2);
            flit.payload.head_data.dest = item.dest;
            flit.payload.head_data.reserved = item.tag;
            scoreboard.add_flit(item.target_ports, item.tag, input_port, flit);

            router_if.driver_cb.in_valid[input_port] <= 1'b1;
            router_if.driver_cb.in_data[input_port] <= flit;

            do begin
                @(router_if.driver_cb);
            end while(router_if.driver_cb.in_ready[input_port] == 1'b0);

            //body flit
            for (int i = 0; i < (item.pkt_len - 2); i++) begin
                flit = '0;
                flit.flit_type = BODY;
                flit.payload.data = item.tag;
                scoreboard.add_flit(item.target_ports, item.tag, input_port, flit);

                router_if.driver_cb.in_valid[input_port] <= 1'b1;
                router_if.driver_cb.in_data[input_port] <= flit;

                do begin
                    @(router_if.driver_cb);
                end while(router_if.driver_cb.in_ready[input_port] == 1'b0);
            end

            //tail flit
            flit = '0;
            flit.flit_type = TAIL;
            flit.payload.data = item.tag;
            scoreboard.add_flit(item.target_ports, item.tag, input_port, flit);

            router_if.driver_cb.in_valid[input_port] <= 1'b1;
            router_if.driver_cb.in_data[input_port] <= flit;

            do begin
                @(router_if.driver_cb);
            end while(router_if.driver_cb.in_ready[input_port] == 1'b0);
            router_if.driver_cb.in_valid[input_port] <= 1'b0;
        end
    endtask
endclass


// class that detects the flits from router and inform the flits to scoreboard
class router_monitor;
    virtual hybrid_router_if    router_if;
    router_scoreboard           scoreboard;

    function new(virtual hybrid_router_if router_if, router_scoreboard scoreboard);
        this.router_if = router_if;
        this.scoreboard = scoreboard;
    endfunction

    task run();
        forever begin
            @(router_if.monitor_cb);
            for (int i = 0; i < NUM_PORTS; i++) begin
                if (router_if.monitor_cb.out_valid[i] && router_if.monitor_cb.out_ready[i]) begin
                    scoreboard.check_flit(i, router_if.monitor_cb.out_data[i]);
                end
            end
        end
    endtask
endclass

// 
class router_env;
    virtual hybrid_router_if    router_if;
    router_scoreboard           scoreboard;
    router_monitor              monitor;
    router_driver               driver  [NUM_PORTS];
    mailbox #(packet_item)      messages [NUM_PORTS];
    int                         router_id;

    function new(virtual hybrid_router_if router_if, int router_id);
        this.router_if = router_if;
        this.scoreboard = new();
        this.monitor = new(router_if, scoreboard);
        for (int i = 0; i < NUM_PORTS; i++) begin
            this.messages[i] = new();
            this.driver[i] = new(router_if, this.scoreboard, this.messages[i], router_id, i);
        end
        if ((router_id < NUM_COLS) || (router_id > (NUM_NODES - NUM_COLS)))
            $fatal(1, "[Time %0t] Env FATAL: Please set router id between (NUM_COLS + 1) ~ (NUM_NODES - NUM_COLS - 1) for router test", $time);
        this.router_id = router_id;
    endfunction

    function port_mask_t get_target_ports(int router_id, dest_t dest);
        int pos_col;
        int pos_row;
        int dst_col;
        int dst_row;
        port_mask_t target_ports;

        pos_col = router_id % NUM_COLS;
        pos_row = router_id / NUM_COLS;
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

    function dest_t get_dest(int dest_list[]);
        dest_t dest;
        
        dest = '0;
        foreach (dest_list[i]) begin
            if ((dest_list[i] >= 0) && (dest_list[i] < NUM_NODES))
                dest[dest_list[i]] = 1'b1;
            else begin
                global_error_cnt++;
                $error("[Time %0t] Packet ERROR: Destination must be within the range of 0 to %0d", $time, NUM_NODES - 1);
            end
        end
        return dest;
    endfunction

    function dest_t correct_dest(int input_port, dest_t dest);
        int pos_col;
        int pos_row;
        int dst_col;
        int dst_row;

        pos_col = router_id % NUM_COLS;
        pos_row = router_id / NUM_COLS;
        for (int k = 0; k < WIDTH_DEST; k++) begin
            if (dest[k]) begin
                dst_col = k % NUM_COLS;
                dst_row = k / NUM_COLS;
                case (input_port) // remove U-turn & Y-axis First case
                    LOCAL_PORT_NUM: begin
                        if (k == router_id)
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

    task configure_router();
        @(router_if.driver_cb);
        for (int i = 0; i < WIDTH_DEST; i++) begin
            router_if.driver_cb.cfg_valid <= 1'b1;
            router_if.driver_cb.cfg_data  <= get_target_ports(router_id, dest_t'(1) << i);

            do begin
                @(router_if.driver_cb);
            end while(router_if.driver_cb.cfg_ready == 1'b0);
        end
        router_if.driver_cb.cfg_valid <= 1'b0;

        @(router_if.driver_cb);
        if (router_if.driver_cb.cfg_ready != 1'b0) begin
            global_error_cnt++;
            $error("[Time %0t] Env ERROR: Router configuration did not end!", $time);
        end
    endtask

    task send_packet(int input_port, int dest_list[], int pkt_len);
        dest_t dest = get_dest(dest_list);
        packet_item item = new(router_id, dest, get_target_ports(router_id, dest), pkt_len, $urandom());
        messages[input_port].put(item);
    endtask

    task send_random_packets(int input_port, int num_pkts);
        packet_item item;
        int pkt_len;
        bit is_ucast;
        int dest_cnt;
        dest_t dest;
        int dest_list[];
        int all_nodes[] = new[NUM_NODES];
        foreach (all_nodes[i])
            all_nodes[i] = i;

        for (int pkt = 0; pkt < num_pkts; pkt++) begin
            pkt_len = $urandom_range(MAX_PKT_LEN, 2);
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
            dest = correct_dest(input_port, get_dest(dest_list));
            if ($countones(dest) == 0) begin
                pkt--;
                continue;
            end
            
            item = new(router_id, dest, get_target_ports(router_id, dest), pkt_len, $urandom());
            messages[input_port].put(item);
        end
    endtask

    task run();
        dest_t dest;
        int output_port;
        
        configure_router();

        fork
            monitor.run();
        join_none
        for (int i = 0; i < NUM_PORTS; i++) begin
            automatic int port_idx = i;
            fork
                driver[port_idx].run();
            join_none
        end
        repeat(10) @(router_if.driver_cb);
        router_if.driver_cb.out_ready <= '1;


        $display("\n[Time %0t] Env: Single unicast packet", $time);
        send_packet(LOCAL_PORT_NUM, '{router_id + 1}, MAX_PKT_LEN); // router_id + 1 : heading east
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Single multicast packet (2 output ports)", $time);
        send_packet(LOCAL_PORT_NUM, '{(router_id - NUM_COLS), (router_id + 1)}, MAX_PKT_LEN); // router_id - NUM_COLS : heading north
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        // router_id -1 : heading west
        // router_id + NUM_COLS : heading south
        $display("\n[Time %0t] Env: Single multicast packet (4 output ports)", $time);
        send_packet(LOCAL_PORT_NUM, '{(router_id - NUM_COLS), (router_id - 1), (router_id + 1), (router_id + NUM_COLS)}, MAX_PKT_LEN);
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Unicast packet and multicast packet without contention", $time);
        send_packet(LOCAL_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{(router_id - NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Contention between unicast packets to check round robin arbitration", $time);
        send_packet(LOCAL_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        repeat(40) @(router_if.driver_cb);
        send_packet(LOCAL_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        send_packet(WEST_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Contention between multicast packets to check fixed priority arbitration", $time);
        send_packet(LOCAL_PORT_NUM, '{(router_id - NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{(router_id + NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Contention between unicast packet and multicast packet to check multicast first arbitration", $time);
        send_packet(LOCAL_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{(router_id + NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);
        

        $display("\n[Time %0t] Env: Check wormhole back-pressure for unicast packet", $time);
        send_packet(LOCAL_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{router_id + NUM_COLS}, MAX_PKT_LEN);
        dest = get_dest('{router_id + NUM_COLS});
        output_port = $clog2(get_target_ports(router_id, dest));
        router_if.driver_cb.out_ready[output_port] <= 1'b0;
        repeat(20) @(router_if.driver_cb);
        router_if.driver_cb.out_ready[output_port] <= '1;
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Check cut-through back-pressure for multicast packet", $time);
        send_packet(LOCAL_PORT_NUM, '{(router_id - NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        send_packet(EAST_PORT_NUM, '{(router_id + NUM_COLS), (router_id - 1)}, MAX_PKT_LEN);
        dest = get_dest('{(router_id - 1)});
        output_port = $clog2(get_target_ports(router_id, dest));
        router_if.driver_cb.out_ready[output_port] <= 1'b0;
        repeat(20) @(router_if.driver_cb);
        router_if.driver_cb.out_ready[output_port] <= '1;
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Inject random packets without back-pressure", $time);
        fork
            begin
                for (int i = 0; i < NUM_PORTS; i++) begin
                    automatic int port_idx = i;
                    fork
                        send_random_packets(port_idx, 10000);
                    join_none
                end
            end
            begin
                repeat(1000000) @(router_if.monitor_cb);
                $display("Simulation Timeout!");
                $display("TEST FAILED");
                $finish;
            end
        join_any
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n[Time %0t] Env: Inject random packets with random back-pressure", $time);
        fork
            begin
                for (int i = 0; i < NUM_PORTS; i++) begin
                    automatic int port_idx = i;
                    fork
                        send_random_packets(port_idx, 10000);
                    join_none
                end
            end
            begin
                forever begin
                    router_if.driver_cb.out_ready <= $urandom_range((1<<NUM_PORTS)-1, 0);
                    repeat($urandom_range(100, 10)) @(router_if.driver_cb);
                    router_if.driver_cb.out_ready <= '1;
                    repeat($urandom_range(100, 10)) @(router_if.driver_cb);
                end
            end
            begin
                repeat(1000000) @(router_if.monitor_cb);
                $display("Simulation Timeout!");
                $display("TEST FAILED");
                $finish;
            end
        join_any
        @(router_if.driver_cb);
        wait(scoreboard.send_cnt == scoreboard.match_cnt);

        // $display("\n[Time %0t] Env: U-turn packet", $time);
        // send_packet(LOCAL_PORT_NUM, '{router_id}, MAX_PKT_LEN);
        // @(router_if.driver_cb);
        // wait(scoreboard.send_cnt == scoreboard.match_cnt);


        $display("\n=========================");
        $display("Simulation End");
        $display("Total Sends: %0d", scoreboard.send_cnt);
        $display("Total Matches: %0d", scoreboard.match_cnt);
        $display("Total Mismatches: %0d", scoreboard.mismatch_cnt);
        $display("Total Errors: %0d", global_error_cnt);

        if ((global_error_cnt == 0) &&(scoreboard.mismatch_cnt == 0) && (scoreboard.send_cnt == scoreboard.match_cnt))
            $display("TEST PASSED");
        else
            $display("TEST FAILED");
        $display("\n=========================");
        $finish();
    endtask
endclass


module hybrid_router_tb();
    parameter CLK_PERIOD = 20;
    parameter ROUTER_ID = 9;

    logic clk;
    logic rst;

    hybrid_router_if router_if(clk);

    hybrid_router #(.ROUTER_ID(ROUTER_ID)) dut (
        .clk(clk),
        .rst(rst),

        .router_if(router_if.router)
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
        .is_mcast_reg(is_mcast_reg),
        .is_obuf_busy_reg(is_obuf_busy_reg)
    );

    bind round_robin_arbiter round_robin_arbiter_sva #(.NUM_REQS(NUM_PORTS)) rr_arb_sva (
        .clk(clk),
        .rst(rst),
        .grant(grant)
    );

    router_env env;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    initial begin
        $timeformat(-9, 2, " ns");

        rst = 1'b1;
        repeat(100) @(negedge clk);
        rst = 1'b0;

        env = new(router_if, ROUTER_ID);
        env.run();
    end
endmodule