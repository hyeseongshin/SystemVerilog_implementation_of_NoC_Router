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
 

package setting_tb;

    localparam CLOCK_PERIOD = 20;
    bit is_network_start = 0;
    time network_start_time;
    time network_end_time;

    int global_error_cnt = 0;

endpackage
