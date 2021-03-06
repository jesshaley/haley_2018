function [ ] = extracellularAnalysis ( )
%Compiles data from a single experiment
%   INPUTS:
%       Choose folder containing unit_bursts.txt files from the output of
%       spikenbursts.s2s as well as .abf files
%   OUTPUTS:
%       data: structure containing all analyzed variables
%   ACCESSORY FILES
%       readSpikeOutput.m: takes .txt files outputted from spikenbursts.s2s
%       and outputs a data structure wity many variables
%       LoadAbf.m: loads abf files into structure

% Query User for Experiment Information
directory=uigetdir(); % get directory

% get burst and abf file names
info.burstFiles = dir(strcat(directory,'/*bursts*.txt')); % find burst files in the directory
info.abfFiles = dir(strcat(directory,'/*_*.abf')); %find abf files in the directory
experimentName = info.abfFiles(1).name(1:7);
for i = 1:length(info.abfFiles) % pull out file names
    info.fileOrder{i,1} = info.abfFiles(i).name;
end

% get unit(s) to analyze
for i = 1:length(info.burstFiles) % pull out unit names
    unitChoice{i} = info.burstFiles(i).name(1:end-11);
end
unitsToAnalyze = listdlg("ListString",unitChoice,...
    "PromptString","Choose the units to analyze :",...
    "SelectionMode","multiple");
info.units = unitChoice(unitsToAnalyze)';

% get protocol order
info.order = questdlg("Which protocol order was used?","Acid of Base First",...
    "AB","BA","AB");

% ask for missing conditions, otherwise, order is assumed
if strcmp(info.order,"AB")
    info.conditions = {'pH 7.8','pH 7.2','pH 6.7','pH 6.1','pH 5.5',...
        'pH 7.8','pH 8.3','pH 8.8','pH 9.3','pH 9.8','pH 10.4','pH 7.8'}';
else
    info.conditions = {'pH 7.8','pH 8.3','pH 8.8','pH 9.3','pH 9.8','pH 10.4',...
        'pH 7.8','pH 7.2','pH 6.7','pH 6.1','pH 5.5','pH 7.8'}';
end
missingCondition = questdlg("Are any of the conditions missing?","Missing Condition",...
    'yes','no','no');
if strcmp(missingCondition,'yes')
    missingCondition = listdlg("ListString",info.conditions,...
        "PromptString","Which condition is missing?",...
        "SelectionMode","single");
    info.conditions{missingCondition} = 'NaN';
    info.fileOrder = [info.fileOrder(1:missingCondition-1);'NaN';...
        info.fileOrder(missingCondition:end)];
end

% sometimes spikenburst.s2s will double/triple count spikes; fix that here
spikeScale = inputdlg('Spike Scale Factor:',...
    'Define Spike Scale Factor',[1 40],{'1'});
info.spikeScaleFactor = str2num(spikeScale{1});

data.info = info;

% Retrieve Time and pH/temp Information
for i = 1:length(info.fileOrder)
    condition = ['condition',num2str(i,'%02d')];
    data.(condition).fileName = info.fileOrder{i};
    data.(condition).condition = info.conditions{i};
    
    try
        abf = LoadAbf(info.fileOrder{i});
        recTime(i,1:2) = [abf.header.recTime(1),abf.header.recTime(2)]; % start and end of file
        recTime(i,3) = recTime(i,2) - recTime(i,1); % file length
        recTime(i,4) = recTime(i,1) - recTime(1,1); % file offset
        
%         [pH_avg,pH_min,pH_sec,T_sec] = convertpH (abf);
%         data.(condition).pH = pH_sec';
%         data.(condition).temp = T_sec';
    end
end
info.sampleFreq = 1000/abf.time(2); % sampling frequency
info.fileStart = recTime(:,1);
info.fileEnd = recTime(:,2);
info.fileLength = recTime(:,3);
info.fileOffset = recTime(:,4);
data.info = info;

% Retrieve and sort Spike2 Output and State Analysis
measures = {'tstart' 'tend' 'spikes' 'duration' 'period' 'hz' 'duty' 'anic'};
for i = 1:length(unitsToAnalyze)
    % run readSpikeOutput on current unit
    unit = info.units{i};
    fileToAnalyze = [directory,'/',info.burstFiles(unitsToAnalyze(i)).name];
    output = readSpikeOutput(fileToAnalyze);
    output.spikes = output.spikes*info.spikeScaleFactor;
    
    % Retrieve State Analysis
    if strcmp(info.units{i}(1:2),'CG')
        analysis = xlsread('stateData_CG.xlsx',[experimentName,'_',unit(1:3)]);
    else
        analysis = xlsread('stateData_STG.xlsx',experimentName);
    end
    analysis = analysis(:,[1 2 5]);
    
    for j = 1:length(info.conditions)
        condition = ['condition',num2str(j,'%02d')];
        
        % pull data from spike2 output and state analysis
        if strcmp(info.fileOrder{j},'NaN')
            includeSpike2 = [];
            includeState = [];
            data.(condition).state = [];
        else
            currentFile = data.(condition).fileName(9:12);
            fileNum = str2num(currentFile);
            includeSpike2 = find(strcmp(output.file,currentFile));
            includeState = find(analysis(:,1) == fileNum);
        end
        
        currentAnalysis = analysis(includeState,[2:3]);
        for k = 1:info.fileLength(j)
            currentState = max(find(currentAnalysis(:,1) < k));
            data.(condition).(unit).state(k,1) = currentAnalysis(currentState,2);
        end
        
        for k = 1:length(measures)
            dataSpike2 = output.(measures{k})(includeSpike2);
            if k == 7
                dataSpike2(dataSpike2 > 0.4) = NaN; % remove duty cycles greater than 0.4
            elseif k == 3 && strcmp(info.units{1}(1:2),'CG')
                dataSpike2(dataSpike2 > 30) = NaN; % remove spikes greater than 30
            elseif k == 3
                dataSpike2(dataSpike2 > 15) = NaN; % remove spikes greater than 30
            end
            data.(condition).(unit).(measures{k}) = dataSpike2';
        end
    end
end

save(strcat(directory,'/data.mat'),'-struct','data'); % save structure

end