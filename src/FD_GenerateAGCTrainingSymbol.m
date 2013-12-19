function [ OutShortTrainingSyms ] = FD_GenerateAGCTrainingSymbol( InShortTrainingSyms, Interpolation )

ShortTrainingSyms_time_64 = ifft(InShortTrainingSyms);
ShortTrainingSyms_time_16 = ShortTrainingSyms_time_64(1:16).';
ShortTrainingSyms_time_160 = repmat(ShortTrainingSyms_time_16,1,10);
ShortTrainingSyms_time_160_I = real(ShortTrainingSyms_time_160);
ShortTrainingSyms_time_160_Q = imag(ShortTrainingSyms_time_160)

[ShortTrainingSyms_wide_time_160_I_inter] = interp(ShortTrainingSyms_time_160_I, Interpolation);
[ShortTrainingSyms_wide_time_160_Q_inter] = interp(ShortTrainingSyms_time_160_Q, Interpolation);

ShortTrainingSyms_wide_time_160_I_inter(end) = ShortTrainingSyms_wide_time_160_I_inter(end)/4;
ShortTrainingSyms_wide_time_160_Q_inter(end) = ShortTrainingSyms_wide_time_160_Q_inter(end)/4;

OutShortTrainingSyms = ShortTrainingSyms_wide_time_160_I_inter + sqrt(-1)*ShortTrainingSyms_wide_time_160_Q_inter;

end

