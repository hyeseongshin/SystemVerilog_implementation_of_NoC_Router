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
 

package setting_noc;

    localparam NUM_COLS         = 8;
    localparam NUM_ROWS         = 6;
    localparam NUM_NODES        = (NUM_COLS * NUM_ROWS);
    localparam MAX_PKT_LEN      = 17;

    localparam DEPTH_OBUF       = MAX_PKT_LEN;

    localparam WIDTH_FLIT_TYPE  = 2;
    localparam WIDTH_FLIT_DATA  = 256;
    localparam WIDTH_FLIT       = (WIDTH_FLIT_TYPE + WIDTH_FLIT_DATA);
    localparam WIDTH_IS_MCAST   = 1;
    localparam WIDTH_DEST       = NUM_NODES; // one-hot encoded

    localparam BYTES_PER_FLIT  = (WIDTH_FLIT_DATA / 8);

    localparam MAX_DATA_BYTES = ((MAX_PKT_LEN - 1) * WIDTH_FLIT_DATA);

    localparam NUM_PORTS        = 5;

    typedef enum logic [WIDTH_FLIT_TYPE-1:0] {HEAD, BODY, TAIL} flit_type_t;
    
    typedef logic [NUM_PORTS-1:0]                   port_mask_t;
    typedef logic [$clog2(NUM_PORTS)-1:0]           port_index_t;
    typedef logic [WIDTH_IS_MCAST-1:0]              is_mcast_t;
    typedef logic [WIDTH_DEST-1:0]                  dest_t;
    typedef logic [$clog2(DEPTH_OBUF):0]            obuf_depth_t;
    typedef logic [$clog2(MAX_DATA_BYTES):0]        valid_bytes_t;

    localparam port_index_t LOCAL_PORT_NUM   = 0;
    localparam port_index_t NORTH_PORT_NUM   = 1;
    localparam port_index_t EAST_PORT_NUM    = 2;
    localparam port_index_t SOUTH_PORT_NUM   = 3;
    localparam port_index_t WEST_PORT_NUM    = 4;

    typedef struct packed 
    {
        is_mcast_t  is_mcast;
        dest_t      dest;
        logic [(WIDTH_FLIT_DATA-$bits(is_mcast_t)-$bits(dest_t))-1:0]  reserved;
    } head_data_t;

    typedef struct packed 
    {
        is_mcast_t      is_mcast;
        dest_t          dest;
        valid_bytes_t   valid_bytes;
        logic [(WIDTH_FLIT_DATA-$bits(is_mcast_t)-$bits(dest_t)-$bits(valid_bytes_t))-1:0]  reserved;
    } head_data_pe_view_t;

    typedef struct packed 
    {
        flit_type_t                     flit_type;

        union packed 
        {
            head_data_t                 head_data;
            head_data_pe_view_t         head_data_pe_view;
            logic [WIDTH_FLIT_DATA-1:0] data;
        } payload;
    } flit_t;

    typedef enum logic [1:0] 
    {
        RST_CFG = 2'b00,
        WAIT_CFG = 2'b01,
        DONE_CFG = 2'b10
    } cfg_state_t;

endpackage
