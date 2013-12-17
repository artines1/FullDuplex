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

ShortTrainingSyms_wide = FD_generate_wideband_AGCTrainSignal(ShortTrainingSyms_wide_freq_64,Wideband_Interpolation_rate);
