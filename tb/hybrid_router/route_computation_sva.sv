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
import setting_tb::*;

module route_computation_sva
(
    input logic                 clk,
    input logic                 rst,

    route_computation_if        rc_if,
    is_mcast_t [NUM_PORTS-1:0]  is_mcast
);

    // XY DOR assumed
    for (genvar i = 0; i < NUM_PORTS; i++) begin : rc_sva
        property p_no_utrun();
            @(posedge clk) disable iff (rst)
            (rc_if.in_valid[i] == 1'b1) |-> (rc_if.request[i][i] != 1'b1);
        endproperty

        property p_no_y_first();
            @(posedge clk) disable iff (rst)
            ((rc_if.in_valid[i] == 1'b1) && ((i == NORTH_PORT_NUM) || (i == SOUTH_PORT_NUM))) |-> 
                    ((rc_if.request[i][EAST_PORT_NUM] != 1'b1) && (rc_if.request[i][WEST_PORT_NUM] != 1'b1));
        endproperty

        property p_check_no_request();
            @(posedge clk) disable iff (rst)
            (rc_if.in_valid[i] == 1'b1) |-> (rc_if.request[i] != 0);
        endproperty


        a_no_uturn:
        assert property (p_no_utrun())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] RC ERROR: Illegal turn (U-turn detected) (Port:%0d)", $time, i);
            end

        a_no_y_first:
        assert property (p_no_y_first())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] RC ERROR: Illegal turn (Y-axis First detected) (Port:%0d)", $time, i);
            end

        a_check_no_request:
        assert property (p_check_no_request())
            else begin 
                global_error_cnt++;
                $error("[Time %0t] RC ERROR: Packet has no request (Port:%0d)", $time, i);
            end
    end


    // check only the packet first inject to the network
    // as the packet moves, even if it is a multicast packet, there may be only one destination due to masking.
    // and it checks destination field of the packet, since even if it is a multicast packet, it requests just one port
    property p_check_mcast();
        @(posedge clk) disable iff (rst)
        ((rc_if.in_valid[LOCAL_PORT_NUM] == 1'b1) && (rc_if.flit_type[LOCAL_PORT_NUM] == HEAD) && (is_mcast[LOCAL_PORT_NUM] == 1'b1)) |-> 
            ($countones(rc_if.dest[LOCAL_PORT_NUM]) >= 2);
    endproperty

    property p_check_ucast();
        @(posedge clk) disable iff (rst)
        ((rc_if.in_valid[LOCAL_PORT_NUM] == 1'b1) && (rc_if.flit_type[LOCAL_PORT_NUM] == HEAD) && (is_mcast[LOCAL_PORT_NUM] != 1'b1)) |-> 
             ($countones(rc_if.dest[LOCAL_PORT_NUM]) == 1);
    endproperty

    a_check_mcast:
    assert property (p_check_mcast())
        else begin 
            global_error_cnt++;
            $error("[Time %0t] RC ERROR: Multicast packet has only one destination", $time);
        end

    a_check_ucast:
    assert property (p_check_ucast())
        else begin 
            global_error_cnt++;
            $error("[Time %0t] RC ERROR: Unicast packet has multiple destinations", $time);
        end


    // always_ff @(posedge clk) begin : rc_sva
    //     if (!rst) begin
    //         for (int i = 0; i < NUM_PORTS; i++) begin
    //             if (rc_if.in_valid[i]) begin
    //                 // XY DOR assumed
    //                 no_uturn : 
    //                 assert( !rc_if.request[i][i] )
    //                     else begin 
    //                         global_error_cnt++;
    //                         $error("[Time %0t] RC ERROR: Illegal turn (U-turn detected) (Port:%0d)", $time, i);
    //                     end
    //                 if ((i == NORTH_PORT_NUM) || (i == SOUTH_PORT_NUM)) begin
    //                     no_y_first :
    //                     assert( !rc_if.request[i][EAST_PORT_NUM] &&
    //                             !rc_if.request[i][WEST_PORT_NUM])
    //                         else begin
    //                             global_error_cnt++;
    //                             $error("[Time %0t] RC ERROR: Illegal turn (Y-axis First detected) (Port:%0d)", $time, i);
    //                         end
    //                 end

    //                 if (rc_if.flit_type[i] == HEAD) begin
    //                     // Check only the packet first inject to the network
    //                     // as the packet moves, even if it is a multicast packet, there may be only one destination due to masking.
    //                     if (i == LOCAL_PORT_NUM) begin
    //                         if (is_mcast[i]) begin
    //                             check_mcast:
    //                             assert($countones(rc_if.dest[i]) >= 2)
    //                                 else begin
    //                                     global_error_cnt++;
    //                                     $error("[Time %0t] RC ERROR: Multicast packet has only one destination (Port:%0d)", $time, i);
    //                                 end
    //                         end
    //                         else begin
    //                             check_ucast:
    //                             assert($countones(rc_if.dest[i]) == 1)
    //                                 else begin
    //                                     global_error_cnt++;
    //                                     $error("[Time %0t] RC ERROR: Unicast packet has multiple destinations (Port:%0d)", $time, i);
    //                                 end
    //                         end
    //                     end
    //                 end
    //             end
    //         end
    //     end
    // end

endmodule