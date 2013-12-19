function [ OutCETrainingSyms ] = FD_GenerateWideCETrainingSignal( InCETrainingSyms, Interpolation)

TrainSignal_time = ifft(InCETrainingSyms).'; 

% Define window for scaling of transitions
% - Scaling option loosely following 802.11 windowing.
% T_TR = 100ns, f_sampling = 40e6, T_sampling = 25ns
% Define Window[n] = sin(pi/2*(0.5+(n-2)/4)) for n in [1,2,3,4]
% Define Window[n] = sin(pi/2*(0.5+(n-62)/4)) for n in [61,62,63,64]
% Define Window[n] = 1 for n in [5:1:60]
Window = [sin(pi/2*(0.5+([1;2;3;4]-2)/4)).^2 ; ones(56,1); sin(pi/2*(0.5-([61;62;63;64]-63)/4)).^2].';

% Apply window
ifft_Out = TrainSignal_time .* Window;

% Concatenate two long training symbols as in standard and add cyclic
TrainSignal_wide_2symsCP_time = [TrainSignal_time(49:64) repmat(TrainSignal_time,1,2) TrainSignal_time(1:16)]; 

% Apply window to begining and end of cyclic extension
TrainSignal_wide_2symsCP_time([1,2,3,4]) = TrainSignal_wide_2symsCP_time([1,2,3,4]) .* Window([1,2,3,4]);
TrainSignal_wide_2symsCP_time([157,158,159,160]) = TrainSignal_wide_2symsCP_time([157,158,159,160]) .* Window([61,62,63,64]);

% Get real and imaginary parts 
TrainSignal_wide_2symsCP_time_I = real(TrainSignal_wide_2symsCP_time);
TrainSignal_wide_2symsCP_time_Q = imag(TrainSignal_wide_2symsCP_time);

% Upsample by 2 so the standard preamble occupies a bandwith of +-10MHz (computed 
[TrainSignal_wide_2symsCP_time_I_inter] = interp(TrainSignal_wide_2symsCP_time_I, Interpolation);
[TrainSignal_wide_2symsCP_time_Q_inter] = interp(TrainSignal_wide_2symsCP_time_Q, Interpolation);

OutCETrainingSyms = TrainSignal_wide_2symsCP_time_I_inter + sqrt(-1)*TrainSignal_wide_2symsCP_time_Q_inter;

end

