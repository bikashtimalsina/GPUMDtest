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

/*----------------------------------------------------------------------------80
The Nose-Hoover chain thermostat
[1] M. E. Tuckerman, Statistical Mechanics: Theory and Molecular Simulation.
Oxford University Press, 2010.
------------------------------------------------------------------------------*/

#include "ensemble_nhc.cuh"
#include "utilities/common.cuh"
#define DIM 3

Ensemble_NHC::Ensemble_NHC(int t, int fg, int mg, double* mv, int N, double T, double Tc, double dt)
{
  type = t;
  fixed_group = fg;
  move_group = mg;
  move_velocity[0] = mv[0];
  move_velocity[1] = mv[1];
  move_velocity[2] = mv[2];
  temperature = T;
  temperature_coupling = Tc;
  // position and momentum variables for one NHC
  pos_nhc1[0] = pos_nhc1[1] = pos_nhc1[2] = pos_nhc1[3] = 0.0;
  vel_nhc1[0] = vel_nhc1[2] = 1.0;
  vel_nhc1[1] = vel_nhc1[3] = -1.0;

  double tau = dt * temperature_coupling;
  double kT = K_B * temperature;
  double dN = DIM * N;
  for (int i = 0; i < NOSE_HOOVER_CHAIN_LENGTH; i++) {
    mas_nhc1[i] = kT * tau * tau;
  }
  mas_nhc1[0] *= dN;
}

Ensemble_NHC::Ensemble_NHC(
  int t,
  int fg,
  int source_input,
  int sink_input,
  int N1,
  int N2,
  double T,
  double Tc,
  double dT,
  double time_step)
{
  type = t;
  fixed_group = fg;
  temperature = T;
  temperature_coupling = Tc;
  delta_temperature = dT;
  source = source_input;
  sink = sink_input;

  // position and momentum variables for NHC
  pos_nhc1[0] = pos_nhc1[1] = pos_nhc1[2] = pos_nhc1[3] = 0.0;
  pos_nhc2[0] = pos_nhc2[1] = pos_nhc2[2] = pos_nhc2[3] = 0.0;
  vel_nhc1[0] = vel_nhc1[2] = vel_nhc2[0] = vel_nhc2[2] = 1.0;
  vel_nhc1[1] = vel_nhc1[3] = vel_nhc2[1] = vel_nhc2[3] = -1.0;

  double tau = time_step * temperature_coupling;
  double kT1 = K_B * (temperature + delta_temperature);
  double kT2 = K_B * (temperature - delta_temperature);
  double dN1 = DIM * N1;
  double dN2 = DIM * N2;
  for (int i = 0; i < NOSE_HOOVER_CHAIN_LENGTH; i++) {
    mas_nhc1[i] = kT1 * tau * tau;
    mas_nhc2[i] = kT2 * tau * tau;
  }
  mas_nhc1[0] *= dN1;
  mas_nhc2[0] *= dN2;

  // initialize the energies transferred from the system to the baths
  energy_transferred[0] = 0.0;
  energy_transferred[1] = 0.0;
}

Ensemble_NHC::~Ensemble_NHC(void)
{
  // nothing now
}

// The Nose-Hover thermostat integrator
// Run it on the CPU, which requires copying the kinetic energy
// from the GPU to the CPU
static double nhc(
  int M,
  double* pos_eta,
  double* vel_eta,
  double* mas_eta,
  double Ek2,
  double kT,
  double dN,
  double dt2_particle)
{
  // These constants are taken from Tuckerman's book
  int n_sy = 7;
  int n_respa = 4;
  const double w[7] = {
    0.784513610477560,
    0.235573213359357,
    -1.17767998417887,
    1.31518632068391,
    -1.17767998417887,
    0.235573213359357,
    0.784513610477560};

  double factor = 1.0; // to be accumulated

  for (int n1 = 0; n1 < n_sy; n1++) {
    double dt2 = dt2_particle * w[n1] / n_respa;
    double dt4 = dt2 * 0.5;
    double dt8 = dt4 * 0.5;
    for (int n2 = 0; n2 < n_respa; n2++) {

      // update velocity of the last (M - 1) thermostat:
      double G = vel_eta[M - 2] * vel_eta[M - 2] / mas_eta[M - 2] - kT;
      vel_eta[M - 1] += dt4 * G;

      // update thermostat velocities from M - 2 to 0:
      for (int m = M - 2; m >= 0; m--) {
        double tmp = exp(-dt8 * vel_eta[m + 1] / mas_eta[m + 1]);
        G = vel_eta[m - 1] * vel_eta[m - 1] / mas_eta[m - 1] - kT;
        if (m == 0) {
          G = Ek2 - dN * kT;
        }
        vel_eta[m] = tmp * (tmp * vel_eta[m] + dt4 * G);
      }

      // update thermostat positions from M - 1 to 0:
      for (int m = M - 1; m >= 0; m--) {
        pos_eta[m] += dt2 * vel_eta[m] / mas_eta[m];
      }

      // compute the scale factor
      double factor_local = exp(-dt2 * vel_eta[0] / mas_eta[0]);
      Ek2 *= factor_local * factor_local;
      factor *= factor_local;

      // update thermostat velocities from 0 to M - 2:
      for (int m = 0; m < M - 1; m++) {
        double tmp = exp(-dt8 * vel_eta[m + 1] / mas_eta[m + 1]);
        G = vel_eta[m - 1] * vel_eta[m - 1] / mas_eta[m - 1] - kT;
        if (m == 0) {
          G = Ek2 - dN * kT;
        }
        vel_eta[m] = tmp * (tmp * vel_eta[m] + dt4 * G);
      }

      // update velocity of the last (M - 1) thermostat:
      G = vel_eta[M - 2] * vel_eta[M - 2] / mas_eta[M - 2] - kT;
      vel_eta[M - 1] += dt4 * G;
    }
  }
  return factor;
}

void Ensemble_NHC::integrate_nvt_nhc_1(
  const double time_step,
  const double volume,
  const std::vector<Group>& group,
  const GPU_Vector<double>& mass,
  const GPU_Vector<double>& potential_per_atom,
  const GPU_Vector<double>& force_per_atom,
  const GPU_Vector<double>& virial_per_atom,
  GPU_Vector<double>& position_per_atom,
  GPU_Vector<double>& velocity_per_atom,
  GPU_Vector<double>& thermo)
{
  const int number_of_atoms = mass.size();

  double kT = K_B * temperature;
  double dN = (double)DIM * number_of_atoms;
  double dt2 = time_step * 0.5;

  const int M = NOSE_HOOVER_CHAIN_LENGTH;
  find_thermo(
    true, volume, group, mass, potential_per_atom, velocity_per_atom, virial_per_atom, thermo);

  double ek2[1];
  thermo.copy_to_host(ek2, 1);
  ek2[0] *= DIM * number_of_atoms * K_B;
  double factor = nhc(M, pos_nhc1, vel_nhc1, mas_nhc1, ek2[0], kT, dN, dt2);
  scale_velocity_global(factor, velocity_per_atom);

  velocity_verlet(
    true, time_step, group, mass, force_per_atom, position_per_atom, velocity_per_atom);
}

void Ensemble_NHC::integrate_nvt_nhc_2(
  const double time_step,
  const double volume,
  const std::vector<Group>& group,
  const GPU_Vector<double>& mass,
  const GPU_Vector<double>& potential_per_atom,
  const GPU_Vector<double>& force_per_atom,
  const GPU_Vector<double>& virial_per_atom,
  GPU_Vector<double>& position_per_atom,
  GPU_Vector<double>& velocity_per_atom,
  GPU_Vector<double>& thermo)
{
  const int number_of_atoms = mass.size();

  double kT = K_B * temperature;
  double dN = (double)DIM * number_of_atoms;
  double dt2 = time_step * 0.5;
  const int M = NOSE_HOOVER_CHAIN_LENGTH;
  double ek2[1];

  velocity_verlet(
    false, time_step, group, mass, force_per_atom, position_per_atom, velocity_per_atom);

  find_thermo(
    true, volume, group, mass, potential_per_atom, velocity_per_atom, virial_per_atom, thermo);

  thermo.copy_to_host(ek2, 1);
  ek2[0] *= DIM * number_of_atoms * K_B;
  double factor = nhc(M, pos_nhc1, vel_nhc1, mas_nhc1, ek2[0], kT, dN, dt2);
  scale_velocity_global(factor, velocity_per_atom);
}

// integrate by one step, with heating and cooling,
// using Nose-Hoover chain method
void Ensemble_NHC::integrate_heat_nhc_1(
  const double time_step,
  const std::vector<Group>& group,
  const GPU_Vector<double>& mass,
  const GPU_Vector<double>& force_per_atom,
  GPU_Vector<double>& position_per_atom,
  GPU_Vector<double>& velocity_per_atom)
{
  int label_1 = source;
  int label_2 = sink;

  int Ng = group[0].number;

  double kT1 = K_B * (temperature + delta_temperature);
  double kT2 = K_B * (temperature - delta_temperature);
  double dN1 = (double)DIM * group[0].cpu_size[source];
  double dN2 = (double)DIM * group[0].cpu_size[sink];
  double dt2 = time_step * 0.5;

  // allocate some memory (to be improved)
  std::vector<double> ek2(Ng);
  GPU_Vector<double> vcx(Ng), vcy(Ng), vcz(Ng), ke(Ng);

  // NHC first
  find_vc_and_ke(group, mass, velocity_per_atom, vcx.data(), vcy.data(), vcz.data(), ke.data());

  ke.copy_to_host(ek2.data());

  double factor_1 =
    nhc(NOSE_HOOVER_CHAIN_LENGTH, pos_nhc1, vel_nhc1, mas_nhc1, ek2[label_1], kT1, dN1, dt2);
  double factor_2 =
    nhc(NOSE_HOOVER_CHAIN_LENGTH, pos_nhc2, vel_nhc2, mas_nhc2, ek2[label_2], kT2, dN2, dt2);

  // accumulate the energies transferred from the system to the baths
  energy_transferred[0] += ek2[label_1] * 0.5 * (1.0 - factor_1 * factor_1);
  energy_transferred[1] += ek2[label_2] * 0.5 * (1.0 - factor_2 * factor_2);

  scale_velocity_local(
    factor_1, factor_2, vcx.data(), vcy.data(), vcz.data(), ke.data(), group, velocity_per_atom);

  velocity_verlet(
    true, time_step, group, mass, force_per_atom, position_per_atom, velocity_per_atom);
}

// integrate by one step, with heating and cooling,
// using Nose-Hoover chain method
void Ensemble_NHC::integrate_heat_nhc_2(
  const double time_step,
  const std::vector<Group>& group,
  const GPU_Vector<double>& mass,
  const GPU_Vector<double>& force_per_atom,
  GPU_Vector<double>& position_per_atom,
  GPU_Vector<double>& velocity_per_atom)
{
  int label_1 = source;
  int label_2 = sink;

  int Ng = group[0].number;

  double kT1 = K_B * (temperature + delta_temperature);
  double kT2 = K_B * (temperature - delta_temperature);
  double dN1 = (double)DIM * group[0].cpu_size[source];
  double dN2 = (double)DIM * group[0].cpu_size[sink];
  double dt2 = time_step * 0.5;

  // allocate some memory (to be improved)
  std::vector<double> ek2(Ng);
  GPU_Vector<double> vcx(Ng), vcy(Ng), vcz(Ng), ke(Ng);

  velocity_verlet(
    false, time_step, group, mass, force_per_atom, position_per_atom, velocity_per_atom);

  // NHC second
  find_vc_and_ke(group, mass, velocity_per_atom, vcx.data(), vcy.data(), vcz.data(), ke.data());

  ke.copy_to_host(ek2.data());
  double factor_1 =
    nhc(NOSE_HOOVER_CHAIN_LENGTH, pos_nhc1, vel_nhc1, mas_nhc1, ek2[label_1], kT1, dN1, dt2);
  double factor_2 =
    nhc(NOSE_HOOVER_CHAIN_LENGTH, pos_nhc2, vel_nhc2, mas_nhc2, ek2[label_2], kT2, dN2, dt2);

  // accumulate the energies transferred from the system to the baths
  energy_transferred[0] += ek2[label_1] * 0.5 * (1.0 - factor_1 * factor_1);
  energy_transferred[1] += ek2[label_2] * 0.5 * (1.0 - factor_2 * factor_2);

  scale_velocity_local(
    factor_1, factor_2, vcx.data(), vcy.data(), vcz.data(), ke.data(), group, velocity_per_atom);
}

void Ensemble_NHC::compute1(
  const double time_step,
  const std::vector<Group>& group,
  Box& box,
  Atom& atom,
  GPU_Vector<double>& thermo)
{
  if (type == 2) {
    integrate_nvt_nhc_1(
      time_step,
      box.get_volume(),
      group,
      atom.mass,
      atom.potential_per_atom,
      atom.force_per_atom,
      atom.virial_per_atom,
      atom.position_per_atom,
      atom.velocity_per_atom,
      thermo);
  } else {
    integrate_heat_nhc_1(
      time_step,
      group,
      atom.mass,
      atom.force_per_atom,
      atom.position_per_atom,
      atom.velocity_per_atom);
  }
}

void Ensemble_NHC::compute2(
  const double time_step,
  const std::vector<Group>& group,
  Box& box,
  Atom& atom,
  GPU_Vector<double>& thermo)
{
  if (type == 2) {
    integrate_nvt_nhc_2(
      time_step,
      box.get_volume(),
      group,
      atom.mass,
      atom.potential_per_atom,
      atom.force_per_atom,
      atom.virial_per_atom,
      atom.position_per_atom,
      atom.velocity_per_atom,
      thermo);
  } else {
    integrate_heat_nhc_2(
      time_step,
      group,
      atom.mass,
      atom.force_per_atom,
      atom.position_per_atom,
      atom.velocity_per_atom);
  }
}
