apx = apx();
apx.inputtermination = '100k'; 
apx.windowType = 'Equiripple';
apx.fftLength = 16384;
apx.averages = 10;
apx.exportPath = 'fftfile.mat';
apx.setVisible(false);
apx.runFFT();
apx.plotPSD();
