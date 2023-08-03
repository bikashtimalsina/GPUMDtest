/*
    Copyright 2017 Zheyong Fan, Ville Vierimaa, Mikko Ervasti, and Ari Harju
    This file is part of GPUMD.
    GPUMD is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    GPUMD is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    You should have received a copy of the GNU General Public License
    along with GPUMD.  If not, see <http://www.gnu.org/licenses/>.
*/

#pragma once

#include "utilities/gpu_vector.cuh"
#include <vector>
class Group;

class Dump_Velocity
{
public:
  void parse(const char** param, int num_param, const std::vector<Group>& groups);
  void preprocess();
  void process(
    const int step,
    const std::vector<Group>& groups,
    GPU_Vector<double>& velocity_per_atom,
    std::vector<double>& cpu_velocity_per_atom);
  void postprocess();

private:
  bool dump_ = false;
  int dump_interval_ = 1;
  int grouping_method_ = -1;
  int group_id_ = -1;
  FILE* fid_;
  char filename_[200];
};
