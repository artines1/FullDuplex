%%%%%
%   The main script for full duplex implement
%%%%%

% Parameter Define Section
Wideband_Interpolation_rate = 2; % Use 2 to achieve 20MHz bandwidth with a sampling frequency of 40MHz                              
ConstellationSize = 4 % Constellation size for full-duplex. Set to QPSK.
NumBitsPerSymbol = log2(ConstellationSize); % Number of bits per symbol for full-duplex
NumSamplesPerSymbol = 80*Wideband_Interpolation_rate; % the number of samples per OFDM (wideband) symbol
ConvCodeRate = 1/2; % Define the convolution code rate
num_previousframes_for_CanChEst = 20; % Define the number of estimates that will be used for avergaging and
                                      % computation of the wire channel.
scale_train_FDMISO_wide = 1/sqrt(1);  % Define scaling factor for training signal for FDMISO widewoband
SI_delay = 28; % Self Interfering channel delay. Delay from tx to rx in the same node


TxDelay = 0;        %Number of noise samples per Rx capture; in [0:2^14]
TxLength = 2^15-1; %Total of samples to transmit; in [0:2^14-TxDelay-1]
CarrierChannel = 11; % Channel in the 2.4 GHz band. In [1:14]
TxMode = 0; % Disable continuous transmission mode
Tx_LowPassFilt = 1;
Rx_LowPassFilt = 2;

Rx_Target = -10;
Rx_NoiseEst = -95;
Rx_AGCTrigger_delay = 50;
Rx_Enable_DCOffset_Correction = 1;
                                 

% Modulation Generator Define Section
Modulator = modem.qammod('M',ConstellationSize,'SymbolOrder','gray','InputType','integer'); % Create Modulator
DeModulator = modem.qamdemod('M',ConstellationSize,'SymbolOrder','gray','OutputType','integer'); % Create DeModulator

ConstellationScalePower = modnorm(Modulator.Constellation,'avpow',1); % Compute scalinig value

% Convolution code define section
trellis_convcode = poly2trellis(7,[133 171]);   % Generate the trellis that will be used to apply the rate 1/2 and rate 2/3
tblen_viterbidec = 4*7;            % Define the traceback length for Viterbi decoding
Puncturing_Rate23code = [1,1,1,0]; % Define puncturing pattern for 2/3 code as per the 802.11 standard

% Define subcarrier mask for training signal for wideband
SubcarrierMask_TrainingWide_freq_bot_32 = ones(32,1);
SubcarrierMask_TrainingWide_freq_top_31 = ones(31,1);

SubcarrierMask_TrainingWide_freq_64 = [SubcarrierMask_TrainingWide_freq_bot_32 ; 0 ; SubcarrierMask_TrainingWide_freq_top_31];
SubcarrierMask_TrainingWide_freq_64 = fftshift(SubcarrierMask_TrainingWide_freq_64);

% Define subcarriers that will not be used for data
SubcarrierMask_PayloadWide_freq_bot_32 = [1, 1, 1, 1, 1, 1, 1, 1,...
    1, 1, 1, 0, 1, 1, 1, 1,...
    1, 1, 1, 1, 1, 1, 1, 1,...
    1, 0, 1, 1, 1, 1, 1, 1].';

SubcarrierMask_PayloadWide_freq_top_31 = [1, 1, 1, 1, 1, 1, 0, 1,...
    1, 1, 1, 1, 1, 1, 1, 1,...
    1, 1, 1, 1, 0, 1, 1, 1,...
    1, 1, 1, 1, 1, 1, 1].';

SubcarrierMask_PayloadWide_freq_64 = [SubcarrierMask_PayloadWide_freq_bot_32 ; 0 ; SubcarrierMask_PayloadWide_freq_top_31];
SubcarrierMask_PayloadWide_freq_64 = fftshift(SubcarrierMask_PayloadWide_freq_64);

Index_subcarriers_maybetraining_nopayload = find(SubcarrierMask_PayloadWide_freq_64==0);

% Initilization WARP Node
Nodes = wl_initNodes(1);

eth_trig = wl_trigger_eth_udp_broadcast;
nodes.wl_triggerManagerCmd('add_ethernet_trigger',[eth_trig]);

[RFA,RFB, RFC, RFD] = wl_getInterfaceIDs(nodes(1));

wl_basebandCmd(Nodes,'tx_delay',TxDelay);
wl_basebandCmd(Nodes,'tx_length',TxLength);
wl_basebandCmd(Nodes,'continuous_tx',TxMode);
wl_interfaceCmd(Nodes,'RF_ALL','channel',2.4,CarrierChannel);

wl_interfaceCmd(Nodes,'RF_ALL','tx_lpf_corn_freq', Tx_LowPassFilt);
wl_interfaceCmd(Nodes,'RF_ALL','rx_lpf_corn_freq', Rx_LowPassFilt);

wl_interfaceCmd(Nodes,'RF_ALL','rx_gain_mode','automatic');
wl_basebandCmd(Nodes,'agc_target', Rx_Target);
wl_basebandCmd(Nodes,'agc_noise_est',Rx_NoiseEst);
wl_basebandCmd(Nodes,'agc_trig_delay', Rx_AGCTrigger_delay);
wl_basebandCmd(Nodes,'agc_dco', Rx_Enable_DCOffset_Correction);

% Generate short training wideband band symbols. 
ShortTrainingSyms_wide_freq_64 = ...
    fftshift([0 0 0 0 0 0 0 0 1+i 0 0 0 -1+i 0 0 0 -1-i 0 0 0 1-i 0 0 0 -1-i 0 0 0 1-i 0 0 0 0 0 0 0 1-i 0 0 0 -1-i 0 0 0 1-i 0 0 0 -1-i 0 0 0 -1+i 0 0 0 1+i 0 0 0 0 0 0 0].');

% Apply subcarrier mask
ShortTrainingSyms_wide_freq_64 = ShortTrainingSyms_wide_freq_64 .* SubcarrierMask_TrainingWide_freq_64;

ShortTrainingSyms_wide = FD_GenerateAGCTrainingSymbol(ShortTrainingSyms_wide_freq_64,Wideband_Interpolation_rate);

% Scale to span -1,1 range of DAC
scale_ShortTrainingSyms_wide = ...
    max([ max(abs(real(ShortTrainingSyms_wide))), max(abs(imag(ShortTrainingSyms_wide))) ]);

ShortTrainingSyms_wide = ShortTrainingSyms_wide * (1/scale_ShortTrainingSyms_wide);

nsamp_ShortTrainingSyms_wide = length(ShortTrainingSyms_wide); % Is equal to 320 samples

% Define Channel Training (Pilot) parameters for wideband channel estimation.
TrainSignal_wide_freq_bot_32 = [0 0 0 0 0 0 1 1 -1 -1 1 1 -1 1 -1 1 1 1 1 1 1 -1 -1 1 1 -1 1 -1 1 1 1 1]';  
TrainSignal_wide_freq_top_31 = [1 -1 -1 1 1 -1 1 -1 1 -1 -1 -1 -1 -1 1 1 -1 -1 1 -1 1 -1 1 1 1 1 0 0 0 0 0]';  
TrainSignal_wide_freq_64 = [TrainSignal_wide_freq_bot_32 ; 0 ; TrainSignal_wide_freq_top_31];  
TrainSignal_wide_freq_64 = fftshift(TrainSignal_wide_freq_64);

% Apply subcarrier mask
TrainSignal_wide_freq_64 = TrainSignal_wide_freq_64 .* SubcarrierMask_TrainingWide_freq_64;

% Call function that generates the training signal for wideband channel
TrainSignal_wide = FD_GenerateWideCETrainingSignal(TrainSignal_wide_freq_64,Wideband_Interpolation_rate);

% Scale to span -1,1 range of DAC
scale_TrainSignal_wide = ...
    max([ max(abs(real(TrainSignal_wide))), max(abs(imag(TrainSignal_wide))) ]);

TrainSignal_wide = TrainSignal_wide * (1/scale_TrainSignal_wide);

nsamp_ChTrainSignal_wide = length(TrainSignal_wide); % Is equal to 320 samples

Result_TrainSignal_wide_PeakDigitalEnergy = max(abs(TrainSignal_wide).^2);
Result_TrainSignal_wide_AvgDigitalEnergy = mean(abs(TrainSignal_wide).^2);

% Define parameters for estimation of RSSI during transmission of wideband training
nsamp_ChTrainSignal_wide_RSSI = nsamp_ChTrainSignal_wide/4; % RSSI ADC is 4 times slower than I/Q ADC

% Create a vector with the indexes of the subcarriers that do not have and
% have  training
subcarriers_without_training = find(TrainSignal_wide_freq_64 == 0);
subcarriers_with_training = find(TrainSignal_wide_freq_64 ~= 0);
num_subcarriers_without_training = length(subcarriers_without_training);
num_subcarriers_with_training = length(subcarriers_with_training);

% These will be the same subcarriers without and with payload
subcarriers_without_payload = union(subcarriers_without_training,Index_subcarriers_maybetraining_nopayload);
subcarriers_with_payload = setdiff([1:1:64],subcarriers_without_payload).';
num_subcarriers_without_payload = length(subcarriers_without_payload);
num_subcarriers_with_payload = length(subcarriers_with_payload);


% Concatenate training with zeros
% We design the training signal so there is a gap of zeros between training
% signals. This helps when plotting/visualization of received samples and
% avoids energy in one training signal leaking to the other because of
% transients. 

TrainZs_wide_InitTune = zeros(1,nsamp_ChTrainSignal_wide); 

Concat_Zeros_Training_wide_InitTune = [TrainZs_wide_InitTune, TrainSignal_wide];
nsamp_Concat_Zeros_Training_wide_InitTune = length(Concat_Zeros_Training_wide_InitTune);

% Specify number of samples to ignore after short training symbols
num_Concat_Zeros_Training_wide_InitTune_ignore_for_DCOSetting = 3;
nsamp_ingore_for_DCOSetting_wide_InitTune = num_Concat_Zeros_Training_wide_InitTune_ignore_for_DCOSetting*nsamp_Concat_Zeros_Training_wide_InitTune;

% Specify number of channel estimates to compute per received frame
num_CE_wideband_InitTune = 5;

% Define parameters that will be used to fill the buffers with training signals.
max_num_ZerosTraining_wide_InitTune = ...
    num_Concat_Zeros_Training_wide_InitTune_ignore_for_DCOSetting + ...
    num_CE_wideband_InitTune;

T1_wide_InitTune_FrameTrain = [ShortTrainingSyms_wide, repmat(Concat_Zeros_Training_wide_InitTune,1,max_num_ZerosTraining_wide_InitTune), TrainZs_wide_InitTune];
T2_wide_InitTune_FrameTrain = [ShortTrainingSyms_wide, repmat(Concat_Zeros_Training_wide_InitTune,1,max_num_ZerosTraining_wide_InitTune), TrainZs_wide_InitTune];
CR1_wide_InitTune_FrameTrain = [ShortTrainingSyms_wide, repmat(Concat_Zeros_Training_wide_InitTune,1,max_num_ZerosTraining_wide_InitTune), TrainZs_wide_InitTune];

nsamp_AGCChannelTrain_InitTune = max([length(T1_wide_InitTune_FrameTrain),...
                             length(T2_wide_InitTune_FrameTrain),length(CR1_wide_InitTune_FrameTrain)]);