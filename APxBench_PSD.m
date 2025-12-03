%% start here
clear
close all
clc

%% API wrapper Handling (custom to where install is located)
NET.addAssembly('C:\Program Files\Audio Precision\APx500 9.1\API\AudioPrecision.API2.dll');

%% Instantiation of APx class 
%make connection between DLL and matlab 
apx = AudioPrecision.API.APx500_Application();

%% basic setup for APx

%Set operating mode to bench (DEFAULT IS SEQUENCE)
apx.OperatingMode = AudioPrecision.API.APxOperatingMode.BenchMode;

% call true/false for calling APx GUI
apx.Visible = true; 
apx.SignalMonitorsEnabled = true;

%% data saving handeling

%create export settings for data
exportsettings = apx.BenchMode.Measurements.Fft.CreateExportSettings();
exportsettings.DataType = AudioPrecision.API.SourceDataType.Measured;


%% Input connection handeling

ch = AudioPrecision.API.InputChannelIndex.Ch1; % set channel
Setup = apx.BenchMode.Setup; % set variable for easier handeling

Setup.AnalogInput; % make sure input is analog
Setup.AnalogInput.ChannelCount = 1; % set amount of channels
Setup.InputConnector.Type = AudioPrecision.API.InputConnectorType.AnalogUnbalanced; % connector type
Setup.AnalogInput.SetTermination(ch, AudioPrecision.API.AnalogInputTermination.InputTermination_Unbal_100k); % input resistance


%% Output connection handeling

%Output connection handling
Setup.OutputConnector.Type = AudioPrecision.API.OutputConnectorType.None;

%% Select FFT in benchmode

%addressing entire Fft branch (ASD,PSD,FFt etc)
sigAn = apx.BenchMode.Measurements.Fft;

% choose fftspectrum from fft measurements and check it so the APx does the measurement
sigAn.FFTSpectrum.Checked = true;

% choose PSD from fft measurement and check it so the APx does the measurement
% sigAn.PowerSpectralDensity.Checked = true;


%% setting up FFT
% settging a window length
sigAn.FFTLength = AudioPrecision.API.FFTLength.FFT_16384;

%Setting up number of averaged (By default power averaged)
sigAn.Averages = 100;

% setting up window type
sigAn.WindowType = AudioPrecision.API.WindowType.Equiripple;

% setup sample rate + bandwith -> read more about apx -> using signal path
apx.BenchMode.Measurements.Fft.AnalogInputBandwidth = AudioPrecision.API.SignalAnalyzerBandwidthType.TrackSetup;

% acquisition type
apx.BenchMode.Measurements.Fft.AcquisitionType = AudioPrecision.API.AcqLengthType.Auto;

%% Start Measurement

% Start the FFT measurement
sigAn.Start();

% Wait for the FFT measurement to finish
    while sigAn.IsStarted 
        pause(0.1); % Pause for a short duration to avoid busy waiting
    end


%% Export data
%data is exported as .mat to a folder
path = 'C:\Users\Ben\OneDrive\Desktop\work\TUE\matlab codes\BEP\Noise\fftfile.mat'; % path + file name 
apx.BenchMode.Measurements.Fft.ExportData(path,AudioPrecision.API.NumberOfGraphPoints.GraphPointsAllPoints,false);

%% data cleaning
load('fftfile.mat')

%handle 4*2 cell
fftdata = FFTSpectrum{4,1};
freq= FFTSpectrum{4,2};

% Basic checks
assert(length(fftdata) == length(freq), 'fftdata and freq must match');

% Frequency resolution
df = freq(2) - freq(1);

% Verify uniform spacing
if max(abs(diff(freq) - df)) > 1e-6
    warning('Frequency bins are not uniformly spaced');
end

% Convert FFT Vrms -> PSD (V^2/Hz)
PSDdata = (abs(fftdata).^2) / df;

% Single-sided FFT correction (exclude DC and Nyquist)
if freq(1) == 0
    PSDdata(2:end-1) = 2 * PSDdata(2:end-1);
end

% Convert to dB(V^2/Hz)
PSDdata_dB = 10*log10(PSDdata);
freq_dB = log10(freq);

% plot
plot(PSDdata_dB,freq_dB)