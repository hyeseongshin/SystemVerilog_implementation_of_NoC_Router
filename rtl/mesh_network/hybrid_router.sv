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

module hybrid_router #(
    parameter ROUTER_ID = 0   
) (
    input   logic               clk,
    input   logic               rst,

    hybrid_router_if.router     router_if
);

    logic           [NUM_PORTS-1:0] ireg_out_valid;
    flit_t          [NUM_PORTS-1:0] ireg_out_data;
    flit_type_t     [NUM_PORTS-1:0] ireg_flit_type;
    dest_t          [NUM_PORTS-1:0] ireg_dest;
    is_mcast_t      [NUM_PORTS-1:0] ireg_is_mcast;

    port_mask_t     [NUM_PORTS-1:0] sa_grant;

    obuf_depth_t    [NUM_PORTS-1:0] obuf_num_free;


    // input registers
    for (genvar i = 0; i < NUM_PORTS; i++) begin : gen_ireg
        input_register_if ireg_if();
        assign ireg_if.in_valid     = router_if.in_valid[i];
        assign ireg_if.in_data      = router_if.in_data[i];

        logic [NUM_PORTS-1:0] grant_transposed;
        for (genvar k = 0; k < NUM_PORTS; k++) begin : gen_grant_mcast_transposed
            assign grant_transposed[k] = sa_grant[k][i];
        end
        // output handshake when request of flit in input register is granted
        assign ireg_if.out_ready = |grant_transposed;

        input_register ireg (
            .clk(clk),
            .rst(rst),

            .ireg_if(ireg_if.ireg)
        );

        assign router_if.in_ready[i]    = ireg_if.in_ready;
        assign ireg_out_valid[i]        = ireg_if.out_valid;
        assign ireg_out_data[i]         = ireg_if.out_data;

        assign ireg_flit_type[i]        = ireg_out_data[i].flit_type;
        assign ireg_dest[i]             = ireg_out_data[i].payload.head_data.dest;
        assign ireg_is_mcast[i]         = ireg_out_data[i].payload.head_data.is_mcast;
    end


    // route computation
    route_computation_if rc_if();
    assign rc_if.cfg_valid      = router_if.cfg_valid;
    assign router_if.cfg_ready  = rc_if.cfg_ready;
    assign rc_if.cfg_data       = router_if.cfg_data;

    assign rc_if.in_valid       = ireg_out_valid;
    assign rc_if.dest           = ireg_dest;
    assign rc_if.flit_type      = ireg_flit_type;

    route_computation rc (
        .clk(clk),
        .rst(rst),

        .rc_if(rc_if.rc)
    );


    // switch allocation
    switch_allocation_if sa_if();
    assign sa_if.in_valid       = ireg_out_valid;
    assign sa_if.flit_type      = ireg_flit_type;
    assign sa_if.is_mcast       = ireg_is_mcast;
    assign sa_if.obuf_num_free  = obuf_num_free;
    assign sa_if.request        = rc_if.request;

    assign sa_grant             = sa_if.grant;

    switch_allocation sa (
        .clk(clk),
        .rst(rst),

        .sa_if(sa_if.sa)
    );


    // switch traversal
    switch_traversal_if st_if();
    assign st_if.in_flit    = ireg_out_data;
    assign st_if.select_id  = sa_if.grant_id;
    assign st_if.mask       = rc_if.mask;

    switch_traversal st (
        st_if.st
    );


    // output buffers
    for (genvar k = 0; k < NUM_PORTS; k++) begin : gen_obuf
        output_buffer_if obuf_if();
        // input handshake when output buffer is granted by any request
        assign obuf_if.in_valid         = |sa_grant[k];
        assign obuf_if.in_data          = st_if.out_flit[k];
        assign obuf_if.out_ready        = router_if.out_ready[k];

        assign router_if.out_valid[k]   = obuf_if.out_valid;
        assign router_if.out_data[k]    = obuf_if.out_data;

        assign obuf_num_free[k]         = obuf_if.num_free;

        output_buffer obuf (
            .clk(clk),
            .rst(rst),

            .obuf_if(obuf_if.obuf)
        );
    end

endmodule
