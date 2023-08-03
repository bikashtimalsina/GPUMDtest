set terminal postscript enhanced color font "arial,12"
set output "Ballistic"
set multiplot layout 2,2
set size square
#set key outside right
set style line 1 lc rgb 'blue' pt 7 ps 0.7
set xlabel "group index"
set ylabel "Temperature(K)"
plot "TempProfile.txt" u 1:2 w linespoints ls 1 noti
set xtics rotate
set ylabel "Heat(eV)"
set xlabel "time(ns)"
plot "EnergyAccumulation.txt" u 1:2 w p pt 6 ps 0.4 lc rgb "red" noti,"" u 1:3 w p pt 6 ps 0.4 lc rgb "blue" noti
set xlabel "Correlation time (ps)"
set ylabel "K (eV/ps)"
plot "CorrelationTime.txt" u 1:2 w l lw 2 lt 1 lc rgb "blue" noti
set xtics norotate
set xlabel "{/Symbol w}/2{/Symbol p}"
set ylabel "G({/Symbol w}) (MW/m^2/K/THz)"
plot "SpectralConductance.txt" u 1:2 w l lw 2 lt 1 lc rgb "blue" noti
!ps2pdf "Ballistic"
system("rm Ballistic")
