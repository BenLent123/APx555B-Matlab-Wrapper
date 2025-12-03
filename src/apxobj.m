classdef apxobj < handle
    % APX  MATLAB wrapper for Audio Precision APx500 FFT → PSD
    
    %% ================= USER CONFIGURATION =================
    properties
        inputtermination = '100k'      % '100k' | '300' | '600' | 'bal200k'
        windowType     = 'Equiripple'
        fftLength      = 16384       % power of 2: 256 → 1248000
        averages       = 10          % power averaging (1–100)
        visible        = true
        exportPath     = 'fftfile.mat'
    end
    
    %% ================= OUTPUT DATA =================
    properties (SetAccess = private)
        fftdata
        freq
        PSDdata
        PSDdata_dB
    end
    
    %% ================= INTERNAL HANDLES =================
    properties (Access = private)
        app
        fftMeas
    end
    
    %% ================= CONSTRUCTOR =================
    methods
        function obj = apxobj()
            obj.loadAPI();
            obj.initApp();
            obj.basicSetup();
            obj.configureFFT();
        end
    end
    
    %% ================= INITIALIZATION =================
    methods (Access = private)
        function loadAPI(~)
            NET.addAssembly( ...
                'C:\Program Files\Audio Precision\APx500 9.1\API\AudioPrecision.API2.dll');
        end
        
        function initApp(obj)
            obj.app = AudioPrecision.API.APx500_Application();
            obj.app.OperatingMode = ...
                AudioPrecision.API.APxOperatingMode.BenchMode;
            obj.app.Visible = obj.visible;
            obj.app.SignalMonitorsEnabled = true;
        end
        
        function basicSetup(obj)
            Setup = obj.app.BenchMode.Setup;
            ch = AudioPrecision.API.InputChannelIndex.Ch1;
            
            % INPUT
            Setup.AnalogInput;
            Setup.AnalogInput.ChannelCount = 1;
            Setup.InputConnector.Type = ...
                AudioPrecision.API.InputConnectorType.AnalogUnbalanced;
            
            obj.applyInputTermination();
            
            % OUTPUT
            Setup.OutputConnector.Type = ...
                AudioPrecision.API.OutputConnectorType.None;
            
            % FFT handle
            obj.fftMeas = obj.app.BenchMode.Measurements.Fft;
            obj.fftMeas.FFTSpectrum.Checked = true;
        end
    end
    
    %% ================= CONFIGURATION =================
    methods (Access = private)
        function applyInputTermination(obj)
            import AudioPrecision.API.*
            Setup = obj.app.BenchMode.Setup;
            ch = InputChannelIndex.Ch1;
            
            switch lower(obj.inputtermination)
                case {'300'}
                    term = AnalogInputTermination.InputTermination_300;
                case {'600'}
                    term = AnalogInputTermination.InputTermination_600;
                case {'100k'}
                    term = AnalogInputTermination.InputTermination_Unbal_100k;
                case {'bal200k'}
                    term = AnalogInputTermination.InputTermination_Bal_200k;
                otherwise
                    error('Unsupported input termination: %s', obj.inputtermination);
            end
            
            Setup.AnalogInput.SetTermination(ch, term);
        end
        
        function configureFFT(obj)
            fft = obj.fftMeas;
            
            obj.validateFFTLength(obj.fftLength);
            obj.validateAverages(obj.averages);
            
            fft.FFTLength = obj.mapFFTLength(obj.fftLength);
            fft.Averages  = obj.averages;
            fft.WindowType = obj.mapWindow(obj.windowType);
            
            fft.AnalogInputBandwidth = ...
                AudioPrecision.API.SignalAnalyzerBandwidthType.TrackSetup;
            
            fft.AcquisitionType = ...
                AudioPrecision.API.AcqLengthType.Auto;
        end
    end
    
    %% ================= MEASUREMENT =================
    methods
        function runFFT(obj)
            % Re-apply settings in case user changed properties
            obj.applyInputTermination();
            obj.configureFFT();
            
            obj.fftMeas.Start();
            while obj.fftMeas.IsStarted
                pause(0.1);
            end
            
            obj.exportFFT();
            obj.processFFT();
        end
        
        function exportFFT(obj)
            obj.fftMeas.ExportData( ...
                obj.exportPath, ...
                AudioPrecision.API.NumberOfGraphPoints.GraphPointsAllPoints, ...
                false);
        end
    end
    
    %% ================= DATA HANDLING =================
    methods (Access = private)
        function processFFT(obj)
            load(obj.exportPath, 'FFTSpectrum');
            
            % --- Handle 4×2 FFTSpectrum cell ---
            temp_fftdata = FFTSpectrum{4,1};
            temp_freq    = FFTSpectrum{4,2};
            
            temp_fftdata = temp_fftdata(:);
            temp_freq    = temp_freq(:);
            
            assert(numel(temp_fftdata) == numel(temp_freq), ...
                'fftdata and freq must match');
            
            df = temp_freq(2) - temp_freq(1);
            
            if max(abs(diff(temp_freq) - df)) > 1e-6
                warning('Frequency bins are not uniformly spaced');
            end
            
            PSD = abs(temp_fftdata).^2 / df;
            
            if temp_freq(1) == 0
                PSD(2:end-1) = 2 * PSD(2:end-1);
            end
            
            obj.fftdata    = temp_fftdata;
            obj.freq       = temp_freq;
            obj.PSDdata    = PSD;
            obj.PSDdata_dB = 10*log10(PSD);
        end
    end
    
    %% ================= USER HELPERS =================
    methods
        function plotPSD(obj)
            plot(log10(obj.freq), obj.PSDdata_dB, 'LineWidth', 1.2);
            grid on;
            xlabel('log_{10}(Frequency)');
            ylabel('PSD (dB(V^2/Hz))');
            title('Power Spectral Density');
        end
        
        function [PSD_dB, freq] = getPSD(obj)
            PSD_dB = obj.PSDdata_dB;
            freq   = obj.freq;
        end
    end
    
    %% ================= VALIDATION =================
    methods (Static, Access = private)
        function validateFFTLength(N)
            valid = N >= 256 && N <= 1248000 && bitand(N, N-1) == 0;
            if ~valid
                error(['FFT length must be a power of 2 between ', ...
                       '256 and 1248000']);
            end
        end
        
        function validateAverages(A)
            if A < 1 || A > 100 || A ~= round(A)
                error('Averages must be an integer between 1 and 100');
            end
        end
    end
    
    %% ================= ENUM MAPPERS =================
    methods (Static, Access = private)
        function val = mapFFTLength(N)
            import AudioPrecision.API.*
            enumName = sprintf('FFT_%d', N);
            try
                val = FFTLength.(enumName);
            catch
                error('FFT length %d not supported by APx enum', N);
            end
        end
        
        function val = mapWindow(w)
            import AudioPrecision.API.*
            switch lower(w)
                case 'equiripple'
                    val = WindowType.Equiripple;
                case 'blackmanharris'
                    val = WindowType.BlackmanHarris;
                case 'blackmanharris4'
                    val = WindowType.BlackmanHarris4;
                case 'dolph150'
                    val = WindowType.Dolph150;
                case 'dolph200'
                    val = WindowType.Dolph200;
                case 'dolph250'
                    val = WindowType.Dolph250;
                case 'flattop'
                    val = WindowType.FlatTop;
                case {'hann','hanning'}
                    val = WindowType.Hann;
                otherwise
                    error('Unsupported window type: %s', w);
            end
        end
    end

    methods
    function help(~) 
        fprintf('\n');
        fprintf('Audio Precision APx MATLAB Wrapper\n');
        fprintf('---------------------------------\n\n');
        
        fprintf('Basic usage:\n\n');
        fprintf('  apx = apx();\n\n');
        
        fprintf('  apx.inputconnector = ''600'';\n');
        fprintf('  apx.windowType     = ''BlackmanHarris4'';\n');
        fprintf('  apx.fftLength      = 65536;\n');
        fprintf('  apx.averages       = 50;\n\n');
        
        fprintf('  apx.runFFT();\n');
        fprintf('  apx.plotPSD();\n\n');
        
        fprintf('Available input connectors:\n');
        fprintf('  ''100k''   (Unbalanced)\n');
        fprintf('  ''300''\n');
        fprintf('  ''600''\n');
        fprintf('  ''bal200k''\n\n');
        
        fprintf('Available window types:\n');
        fprintf('  Equiripple\n');
        fprintf('  BlackmanHarris\n');
        fprintf('  BlackmanHarris4\n');
        fprintf('  Dolph150 | Dolph200 | Dolph250\n');
        fprintf('  FlatTop\n');
        fprintf('  Hann\n\n');
        
        fprintf('FFT length:\n');
        fprintf('  Power of 2 from 256 → 1248000\n\n');
        
        fprintf('Averages:\n');
        fprintf('  Integer from 1 → 100 (power averaged)\n\n');
        
        fprintf('Example:\n');
        fprintf('---------------------------------\n');
        fprintf('  apx = apx();\n');
        fprintf('  apx.inputconnector = ''600'';\n');
        fprintf('  apx.windowType     = ''BlackmanHarris4'';\n');
        fprintf('  apx.fftLength      = 65536;\n');
        fprintf('  apx.averages       = 50;\n');
        fprintf('  apx.runFFT();\n');
        fprintf('  apx.plotPSD();\n\n');
    end
   
   
    end

    methods
    function setVisible(obj, flag)
        if ~islogical(flag)
            error('Visible flag must be true or false');
        end

        obj.visible = flag;
        obj.app.Visible = flag;
    end
end


end
