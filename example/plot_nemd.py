from pylab import *
from thermo.gpumd.io import ase_atoms_to_gpumd
from thermo.gpumd.preproc import add_group_by_position
from thermo.gpumd.data import load_shc,load_compute
from ase.build import graphene_nanoribbon
from ase.io import read
from ase.io import write
import matplotlib.pyplot as plt
import numpy as np

compute=load_compute(['T'])
print(compute.keys())
T=compute['T']
Ein=compute['Ein']
Eout=compute['Eout']
ndata=T.shape[0]
temp_ave=mean(T[int(ndata/2)+1:,1:],axis=0)
print(temp_ave)

dt=0.001 # time in ps
Ns=1000 # sample interval
t=dt*np.arange(1,ndata+1)*Ns/1000 #ns

# Temperature profile in the NEMD simulation
group_idx=range(1,10)
#plt.plot(group_idx,temp_ave,linewidth=3,marker='o',markersize=10)
with open("TempProfile.txt","w") as file:
    for i in range(len(group_idx)):
        file.writelines("{} {}".format(group_idx[i],temp_ave[i]))
        file.writelines("\n")
file.close()
#plt.xlim([1,4])
#plt.show()

# Energies accumulated in the thermostats
with open("EnergyAccumulation.txt","w") as file:
    file.writelines("t(ps)  Energy-in(Ein)  Energy-out(Eout)")
    for i in range(len(t)):
        file.writelines("{} {} {}".format(t[i],Ein[i],Eout[i]))
        file.writelines("\n")
file.close()
#plt.plot(t,Ein,'C3',linewidth=3)
#plt.plot(t,Eout,'C0',linewidth=3,linestyle='--')
#plt.show()

# Spectral heat current results

deltaT=temp_ave[0]-temp_ave[-1] # Unit in K
Q1=(Ein[int(ndata/2)]-Ein[-1])/(ndata/2)/dt/Ns
Q2=(Eout[-1]-Eout[int(ndata/2)])/(ndata/2)/dt/Ns
Q=mean([Q1,Q1])  # Unit eV/ps
# Cell length l=[lx,ly,lz]
l=[41.948415859093096,41.948415859093096,41.948415859093096]  # Unit A
A=l[0]*l[1]   # Unit A**2
Vall=A*l[2] # Unit A**3
#G=160*Q/deltaT/A   # Unit is GW/m**2/K  # 160 is conversion factor
G=1.6*10**5*Q/deltaT/A # Unit is MW/m**2/K
# Load spectral heat current file
shc=load_shc(250,1000)['run0']
print(shc.keys)
Lx=l[0]
Ly=4.1948415859093096
Lz=l[2] #-0.454516
V=Lx*Ly*Lz
Gc=1.6*10**4*(shc['jwi']+shc['jwo'])/V/deltaT

# Plot correlation time
corr_time=(shc['Ki']+shc['Ko'])/Ly
with open("CorrelationTime.txt","w") as file:
    file.writelines("correlation time(ps) correlation function(ev/ps)")
    for i in range(len(corr_time)):
        file.writelines("{} {}".format(shc['t'][i],corr_time[i]))
        file.writelines("\n")
file.close()
#plt.plot(shc['t'],(shc['Ki']+shc['Ko'])/lz,linewidth=2)
#plt.show()

# Plot spectral thermal conductance
with open("SpectralConductance.txt","w") as file:
    file.writelines("frequency(THz), Spectral conductance(GW/m^2/K/THz)")
    for i in range(len(Gc)):
        file.writelines("{} {}".format(shc['nu'][i],Gc[i]))
        file.writelines("\n")
file.close()
plt.plot(shc['nu'],Gc,linewidth=2)
#plt.xlim([0,60])
plt.show()

np.save("./Gc.npy",Gc)
