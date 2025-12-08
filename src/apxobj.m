classdef apxobj < handle
    % APX  MATLAB wrapper for Audio Precision APx500 FFT → PSD

    %% ================= USER CONFIGURATION =================
    properties
        inputtermination = '100k'      % '100k' | '300' | '600' | 'bal200k'
        windowType       = 'Equiripple'
        fftLength        = 16384
        averages         = 10
        visible          = false

        exportDir  = ...
            'C:\Users\Ben\OneDrive\Desktop\work\TUE\matlab codes\BEP\Noise'
        exportFile = ''     % auto-generated per run
    end

    %% ================= OUTPUT DATA =================
    properties (SetAccess = private)
        fftdata
        freq
        PSDdata
        PSDdata_dB
        scopedata
        time
    end

    %% ================= INTERNAL HANDLES =================
    properties (Access = private)
        app
        fftMeas
        lastExportPath
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

            Setup.AnalogInput.ChannelCount = 1;
            Setup.InputConnector.Type = ...
                AudioPrecision.API.InputConnectorType.AnalogUnbalanced;

            obj.applyInputTermination();

            Setup.OutputConnector.Type = ...
                AudioPrecision.API.OutputConnectorType.None;

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
                case '300'
                    term = AnalogInputTermination.InputTermination_300;
                case '600'
                    term = AnalogInputTermination.InputTermination_600;
                case '100k'
                    term = AnalogInputTermination.InputTermination_Unbal_100k;
                case 'bal200k'
                    term = AnalogInputTermination.InputTermination_Bal_200k;
                otherwise
                    error('Unsupported input termination');
            end

            Setup.AnalogInput.SetTermination(ch, term);
        end

        function configureFFT(obj)
            fft = obj.fftMeas;

            obj.validateFFTLength(obj.fftLength);
            obj.validateAverages(obj.averages);

            fft.FFTLength  = obj.mapFFTLength(obj.fftLength);
            fft.Averages   = obj.averages;
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
            obj.applyInputTermination();
            obj.configureFFT();

            obj.fftMeas.Start();
            while obj.fftMeas.IsStarted
                pause(0.1);
            end

            obj.exportFFT();
            obj.processFFT();
        end
    end

    %% ================= EXPORT =================
    methods (Access = private)
        function p = makeExportPath(obj)
            if isempty(obj.exportFile)
                ts = datetime('now', 'Format', 'yyyy-MM-dd_HHmmss');
                obj.exportFile = ['fft_' char(ts) '.mat']; 
            end

            p = fullfile(obj.exportDir, obj.exportFile);
            obj.lastExportPath = p;
        end

        function exportFFT(obj)
            p = obj.makeExportPath();

            obj.fftMeas.ExportData( ...
                p, ...
                AudioPrecision.API.NumberOfGraphPoints.GraphPointsAllPoints, ...
                false);

            if ~exist(p,'file')
                error('APx export failed');
            end
        end
    end

    %% ================= DATA HANDLING =================
    methods (Access = private)
        function processFFT(obj)
            S = load(obj.lastExportPath);

            FFTSpectrum = S.FFTSpectrum;
            Scope       = S.Scope;

            % FFT
            obj.fftdata = FFTSpectrum{4,2}(:);
            obj.freq    = FFTSpectrum{4,1}(:);

            % Time domain
            obj.time      = Scope{4,1}(:);
            obj.scopedata = Scope{4,2}(:);

            df = obj.freq(2) - obj.freq(1);

            PSD = abs(obj.fftdata).^2 / df;
            if obj.freq(1) == 0
                PSD(2:end-1) = 2 * PSD(2:end-1);
            end

            obj.PSDdata    = PSD;
            obj.PSDdata_dB = 10*log10(PSD);
        end
    end

    %% ================= USER API =================
    methods
        function data = returndata(obj)
            data = struct( ...
                'fft',     obj.fftdata, ...
                'freq',    obj.freq, ...
                'PSD',     obj.PSDdata, ...
                'PSD_dB',  obj.PSDdata_dB, ...
                'scope',   obj.scopedata, ...
                'time',    obj.time );
        end

        function plotPSD(obj)
            figure;
            plot(log10(obj.freq), obj.PSDdata_dB,'LineWidth',1.2)
            grid on
            xlabel('log_{10}(Frequency)')
            ylabel('PSD (dB(V^2/Hz))')
            title('Power Spectral Density')
        end

        function plotFFT(obj)
            figure;
            plot(log10(obj.freq),obj.fftdata,'LineWidth',1.2)
            grid on
            xlabel('log_{10}(Frequency)')
            ylabel('FFT (V_{rms})')
            title('FFT')
        end
    end

    methods
    function setvisible(obj, flag)
        % setVisible(true/false)
        % Simple handler to turn APx GUI visibility ON or OFF.

        % Convert input to logical
        obj.visible = logical(flag);

        % If APx application isn't created yet, just warn and return
        if isempty(obj.app)
            warning('APx application handle not initialized yet.');
            return;
        end

        % Apply visibility to APx application
        obj.app.Visible = obj.visible;

        % If turning ON, try to force the GUI to appear
        if obj.visible
            try
                obj.app.ShowWindow();   % Not all APx versions have this
            catch
                % Quiet: not an error, just means API version lacks ShowWindow
            end
        end
    end
end
    %% ================= VALIDATION =================
    methods (Static, Access = private)
        function validateFFTLength(N)
            if N < 256 || bitand(N,N-1) ~= 0
                error('FFT length must be power of 2 >= 256');
            end
        end

        function validateAverages(A)
            if A < 1 || A > 100 || A ~= round(A)
                error('Averages must be integer 1–100');
            end
        end
    end

    %% ================= ENUM MAPPERS =================
    methods (Static, Access = private)
        function val = mapFFTLength(N)
            import AudioPrecision.API.*
            val = FFTLength.(sprintf('FFT_%d',N));
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
                case 'hann'
                    val = WindowType.Hann;
                otherwise
                    error('Unsupported window');
            end
        end
    end
end
