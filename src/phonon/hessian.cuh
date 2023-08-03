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
#include <fstream>
#include <iostream>
#include <stdio.h>
#include <vector>

class Box;
class Group;
class Force;

class Hessian
{
public:
  double displacement = 0.005;
  double cutoff = 4.0;

  void compute(
    Force& force,
    Box& box,
    std::vector<double>& cpu_position_per_atom,
    GPU_Vector<double>& position_per_atom,
    GPU_Vector<int>& type,
    std::vector<Group>& group,
    GPU_Vector<double>& potential_per_atom,
    GPU_Vector<double>& force_per_atom,
    GPU_Vector<double>& virial_per_atom);

  void parse(const char**, size_t);

protected:
  size_t num_basis;
  size_t num_kpoints;

  std::vector<size_t> basis;
  std::vector<size_t> label;
  std::vector<double> mass;
  std::vector<double> kpoints;
  std::vector<double> H;
  std::vector<double> DR;
  std::vector<double> DI;

  void read_basis(size_t N);
  void read_kpoints();
  void initialize(size_t);
  void finalize(void);

  void find_H(
    Force& force,
    Box& box,
    std::vector<double>& cpu_position_per_atom,
    GPU_Vector<double>& position_per_atom,
    GPU_Vector<int>& type,
    std::vector<Group>& group,
    GPU_Vector<double>& potential_per_atom,
    GPU_Vector<double>& force_per_atom,
    GPU_Vector<double>& virial_per_atom);

  bool is_too_far(
    const Box& box,
    const std::vector<double>& cpu_position_per_atom,
    const size_t n1,
    const size_t n2);

  void find_dispersion(const Box& box, const std::vector<double>& cpu_position_per_atom);

  void find_D(const Box& box, std::vector<double>& cpu_position_per_atom);

  void find_eigenvectors();
  void output_D();
  void find_omega(FILE*, size_t);
  void find_omega_batch(FILE*);
};
