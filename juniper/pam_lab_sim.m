%% Calculate BER of amplified IM-DD system similar to the system in the lab
% - Detection is done using a coherent receiver
% - Booster amplifier at the transmitter completely compensates for fiber
% attenuation and other losses
% - Pre-amplifier at the receiver makes received power constant
% - CD is partially compensated by DCF
% - Equalization is done using a fractionally spaced linear equalizer
% Simulations include modulator, fiber, optical amplifier characterized 
% only by gain and noise figure, optical bandpass filter, antialiasing 
% filter, sampling, and linear equalization

clear, clc

addpath f/ % Juniper project specific functions
addpath ../mpam % PAM
addpath ../f % general functions
addpath ../soa % for pre-amplifier 
addpath ../apd % for PIN photodetectors

%% Transmit power swipe
Tx.PtxdBm = -28:-5; % transmitter power range
% Tx.PtxdBm = -25; % transmitter power range

%% Simulation parameters
sim.Rb = 56e9;    % bit rate in bits/sec
sim.Nsymb = 2^16; % Number of symbols in montecarlo simulation
sim.ros.txDSP = 2; % oversampling ratio transmitter DSP (must be integer). DAC samping rate is sim.ros.txDSP*mpam.Rs
% For DACless simulation must make Tx.dsp.ros = sim.Mct and DAC.resolution = Inf
sim.ros.rxDSP = 2; % oversampling ratio of receiver DSP. If equalization type is fixed time-domain equalizer, then ros = 1
sim.Mct = 2*5;      % Oversampling ratio to simulate continuous time. Must be integer multiple of sim.ros.txDSP and numerator of sim.ros.rxDSP
% sim.Me = 16;       % Number of used eigenvalues
% sim.L = 2; % de Bruijin sub-sequence length (ISI symbol length)
sim.BERtarget = 1e-4; 
sim.Ndiscard = 1024; % number of symbols to be discarded from the begning and end of the sequence
sim.N = sim.Mct*sim.Nsymb; % number points in 'continuous-time' simulation
sim.Modulator = 'MZM'; % 'MZM' only
 
%% Simulation control
sim.PrxdBm = 14; % constant received power
sim.preAmp = true;
sim.labSetup = true;
sim.coherentReceiver = false;
sim.modulatorPreemphasis = true;
sim.duobinary = true;
sim.preemphRange = 25e9;
sim.mzm_predistortion = 'levels';
sim.RIN = true; % include RIN noise in montecarlo simulation
sim.phase_noise = true; % whether to simulate laser phase noise
sim.PMD = false; % whether to simulate PMD
sim.quantiz = true; % whether quantization is included
sim.stopSimWhenBERReaches0 = true; % stop simulation when counted BER reaches 0

% Control what should be plotted
sim.Plots = containers.Map();
sim.Plots('BER') = 1;
sim.Plots('DAC output') = 0;
sim.Plots('Optical eye diagram') = 0;
sim.Plots('Signal after equalization') = 1;
sim.Plots('Equalizer') = 1;
% sim.Plots('Adaptation MSE') =1;
% sim.Plots('Channel frequency response') = 1;
sim.Plots('OSNR') = 0;
sim.Plots('Received signal optical spectrum') = 0;
sim.Plots('PAM levels MZM predistortion') = 0;
sim.shouldPlot = @(x) sim.Plots.isKey(x) && sim.Plots(x);

%% Pulse shape
pulse_shape = select_pulse_shape('rect', sim.ros.txDSP);
% pulse_shape = select_pulse_shape('rrc', sim.ros.txDSP, 0.2, 4);
Tx.pulse_shape = pulse_shape;

%% M-PAM
% PAM(M, bit rate, leve spacing : {'equally-spaced', 'optimized'}, pulse
% shape: struct containing properties of pulse shape 
mpam = PAM(4, sim.Rb, 'equally-spaced', pulse_shape);

%% Time and frequency
sim.fs = mpam.Rs*sim.Mct;  % sampling frequency in 'continuous-time'
[sim.f, sim.t] = freq_time(sim.N, sim.fs);

%% Transmitter
Tx.rexdB = -20;  % extinction ratio in dB. Defined as Pmin/Pmax
Tx.alpha = 0; % chirp parameter for laser or modulator

%% DAC
Tx.DAC.fs = sim.ros.txDSP*mpam.Rs; % DAC sampling rate
Tx.DAC.ros = sim.ros.txDSP; % oversampling ratio of transmitter DSP
Tx.DAC.resolution = 6; % DAC effective resolution in bits
% Tx.DAC.filt = design_filter('butter', 3, 20e9/(sim.fs/2)); % DAC analog frequency response
Tx.DAC.filt = design_filter('bessel', 5, 30e9/(sim.fs/2)); % DAC analog frequency response
Tx.DAC.rclip = 0;

%% Laser
% Laser constructor: laser(lambda (nm), PdBm (dBm), RIN (dB/Hz), linewidth (Hz), frequency offset (Hz))
% lambda : wavelength (nm)
% PdBm : output power (dBm)
% RIN : relative intensity noise (dB/Hz)
% linewidth : laser linewidth (Hz)
% freqOffset : frequency offset with respect to wavelength (Hz)
Tx.Laser = laser(1550e-9, 0, -150, 0.2e6, 0);

%% Modulator
% Tx.Mod.type = sim.Modulator;    
% Tx.Mod.BW = 15e9;
% Tx.Mod.fc = Tx.Mod.BW/sqrt(sqrt(2)-1); % converts to relaxation frequency
% Tx.Mod.grpdelay = 2/(2*pi*Tx.Mod.fc);  % group delay of second-order filter in seconds
% Tx.Mod.H = exp(1j*2*pi*f*Tx.Mod.grpdelay)./(1 + 2*1j*f/Tx.Mod.fc - (f/Tx.Mod.fc).^2);  % laser freq. resp. (unitless) f is frequency vector (Hz)

Tx.Mod.type = sim.Modulator;    
Tx.Mod.Vbias = 0*0.47; % bias voltage normalized by Vpi
Tx.Mod.Vswing = 2*0.31;  % normalized voltage swing. 1 means that modulator is driven at full scale
Tx.Mod.Vgain = 2.4; % 2.4 gain to compensate for preemphasis 
% Tx.Mod.BW = 30e9;
% Tx.Mod.filt = design_filter('bessel', 5, Tx.Mod.BW/(sim.fs/2));
% Tx.Mod.H = Tx.Mod.filt.H(sim.f/sim.fs);

fit3 = [-0.0013 0.5846 1.5859];
Hpreemph = 10.^(polyval([-0.0013 0.5846 1.5859], abs(sim.f/1e9))/20);
Tx.Mod.H =  1./Hpreemph;
Tx.Mod.H =  Tx.Mod.H/interp1(sim.f, Tx.Mod.H, 0);
Tx.Mod.BW = interp1(Tx.Mod.H(sim.f > 0), sim.f(sim.f > 0),  0.5);

%% Fiber
% fiber(Length in m, anonymous function for attenuation versus wavelength
% (default: att(lamb) = 0 i.e., no attenuation), anonymous function for 
% dispersion versus wavelength (default: SMF28 with lamb0 = 1310nm, S0 = 0.092 s/(nm^2.km))
SMF = fiber(10*(20/17)*1e3); 
DCF = fiber(0, @(lamb) 0, @(lamb) -0.1*(lamb-1550e-9)*1e3 - 40e-6); 

Fibers = [SMF DCF];

% Tx.predist = design_predistortion_filter(15, mpam.Rs*sim.ros.txDSP, Fibers(1), Tx.Laser.wavelength, true);

%% Amplifier
% Class SOA characterizes amplifier in terms of gain and noise figure
% soa(GaindB: amplifier gain in dB, NFdB: noise figure in dB, lambda: operationa wavelength, maxGaindB: maximum amplifier gain) 
EDFA = soa(20, 5, 1550e-9, 20); 

%% Photodiode
% pin(R: Responsivity (A/W), Id: Dark current (A), BW: bandwidth (Hz))
% PIN frequency response is modeled as a first-order system
Rx.PD = pin(1, 10e-9, Inf);

%% Receiver
% One-sided thermal noise PSD
Rx.N0 = (30e-12).^2; 
Rx.PlodBm = 16; % Local oscillator power

% Optical Bandpass Filter (fiber Brag gratting)
Rx.optfilt = design_filter('fbg', 4, 200e9/(sim.fs/2));

Rx.filtering = 'antialiasing'; % {'antialiasing' or 'matched'}

if isfield(sim, 'coherentReceiver') && sim.coherentReceiver
    %% ADC = DSO
    Rx.ADC.fs = 80e9;
    Rx.ADC.ros = Rx.ADC.fs/mpam.Rs;
    Rx.ADC.filt = design_filter('butter', 5, 30e9/(sim.fs/2)); % Antialiasing filter
    Rx.ADC.ENOB = 5; % effective number of bits. Quantization is only included if sim.quantiz = true and ENOB ~= Inf
    Rx.ADC.rclip = 0;
else
    %% ADC for direct detection case
    Rx.ADC.fs = mpam.Rs*sim.ros.rxDSP;
    Rx.ADC.ros = sim.ros.rxDSP;
    Rx.ADC.filt = design_filter('butter', 5, (Rx.ADC.fs/2)/(sim.fs/2)); % Antialiasing filter
    Rx.ADC.ENOB = 5; % effective number of bits. Quantization is only included if sim.quantiz = true and ENOB ~= Inf
    Rx.ADC.rclip = 0;
end

%% Equalizer
% Terminology: TD = time domain, SR = symbol-rate, LE = linear equalizer
Rx.eq.ros = sim.ros.rxDSP;
Rx.eq.type = 'Adaptive TD-LE';
Rx.eq.Ntaps = 5;
Rx.eq.mu = 1e-3;
Rx.eq.Ntrain = 1e4; % Number of symbols used in training (if Inf all symbols are used)
Rx.eq.Ndiscard = [1.5e4 1024]; % symbols to be discard from begining and end of sequence due to adaptation, filter length, etc

%% Generate summary
generate_summary(mpam, Tx, Fibers, EDFA, Rx, sim);

% load('Hpreemph')
% Tx.Hpreemph = Hpreemph;
% Tx.Hpreemph = calculate_fiber_preemphasis(21, Tx.Laser.wavelength, Fibers(1), Rx.ADC.filt.H(sim.f/sim.fs), sim);

%% Run simulation
[BER, OSNRdB] = preamplified_sys_ber(mpam, Tx, Fibers, EDFA, Rx, sim)

% figure(1), hold on
% load('PAM4_experiment_summary');
% plot(Experiment('PAM4_56G_BER_vs_OSNR_0km_set1').OSNRdB, log10(Experiment('PAM4_56G_BER_vs_OSNR_0km_set1').BER.count),...
%     '-ok', 'LineWidth', 2, 'DisplayName', 'Experiment 1')
% plot(Experiment('PAM4_56G_BER_vs_OSNR_0km_set2').OSNRdB, log10(Experiment('PAM4_56G_BER_vs_OSNR_0km_set2').BER.count),...
%     '-ok', 'LineWidth', 2, 'DisplayName', 'Experiment 2')
% plot(Experiment('PAM4_56G_BER_vs_OSNR_10km_set1').OSNRdB, log10(Experiment('PAM4_56G_BER_vs_OSNR_10km_set1').BER.count),...
%     '-ok', 'LineWidth', 2, 'DisplayName', 'Experiment 3')
% legend('-DynamicLegend')