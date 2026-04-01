function reflexBetaStandAlone
% FUNCTION reflexPupillometerBeta is a wrapper-code designed to measure the
% rate of pupil dilation in the presence of visible stimulation. This code
% is broken into the following blocks:

tic
[fileBase,pathName,~] = uigetfile({'*.*'},'File Selector');
[pathName,fileBase,fileExt]  = fileparts(fullfile(pathName,fileBase));      % Parse through file name parts
vidName  =  fullfile(pathName,[fileBase,fileExt]);                          % Rebuild filename
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% VIDEO READER AND IMAGE LOADER BLOCK START %%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
vid     = VideoReader(vidName);                                             % Load video using reader
fStart  = floor(1.0*vid.FrameRate)+1;                                       % Set Start frame number (0.8 seconds in)
tEnd    = 5.5;                                                              % Set approximate end time (at 5.8 seconds)
vid.CurrentTime = fStart/vid.FrameRate;                                     % Set Current Time to start frame
frameTimeSeries = linspace(1,vid.FrameRate*vid.Duration,...
    vid.FrameRate*vid.Duration)/vid.FrameRate;                              % Generate frame time series
capTime     = find(frameTimeSeries <= tEnd);                                % Use end time to find cut-off
deltaTime   = vid.FrameRate;
% CHECK VIDEO SIZES TO MAKE SURE THAT VIDEO IS ORIENTED & SIZED CORRECTLY
if vid.Height > vid.Width
    if vid.Height > 1920 && vid.Width > 1080
        videoDims = [1920, 1080, 3, (capTime(end)-(fStart-1))];             % Get loaded video dimensions
    else
        videoDims = [vid.Height, vid.Width, 3, (capTime(end)-(fStart-1))];  % Get loaded video dimensions
    end
    video   = uint8(zeros(videoDims));                                      % Preallocate memory for video images
    counter = 1;                                                            % Initialize video read counter
    while vid.CurrentTime <= tEnd && vid.CurrentTime < vid.Duration
        video(:,:,:,counter) = imresize(readFrame(vid),...
            [videoDims(1) videoDims(2)],'nearest');                         % Read in video using readFrame
        counter = counter + 1;                                              % Update video read counter
    end
elseif vid.Height < vid.Width
    if vid.Width > 1080 && vid.Height > 1920
        videoDims = [1920, 1080, 3, (capTime(end)-(fStart-1))];             % Get loaded video dimensions
    else
        videoDims = [vid.Width, vid.Height, 3, (capTime(end)-(fStart-1))];  % Get loaded video dimensions
    end
    video   = uint8(zeros(videoDims));                                      % Preallocate memory for video images
    counter = 1;                                                            % Initialize video read counter
    while vid.CurrentTime <= tEnd && vid.CurrentTime < vid.Duration
        video(:,:,:,counter) = imresize(permute(readFrame(vid),[2 1 3]),...
            [videoDims(1) videoDims(2)],'nearest');                         % Read in video using readFrame
        counter = counter + 1;                                              % Update video read counter
    end
end
video(:,:,:,counter:end) = [];                                              % Remove any extra empty frames
if counter > size(video,4)
    counter = size(video,4);
end
frskip      = 1;                                                            % Frame skip index values
frsrs       = linspace(0,counter-1,counter)+fStart;                         % Build frame series vector
video       = video(:,:,:,frskip:frskip:end);                               % Store final video series that will be processed
videoDims   = size(video);                                                  % Get new video dimensions
frameMedian = double(mean(reshape(video,...
    videoDims(1)*videoDims(2)*videoDims(3),videoDims(4)),1));               % Compute mean of each frame                                         % Find indices equal to 1 (too bright)
tInd = find(frameMedian < quantile(frameMedian,0.25)-10*iqr(frameMedian) |...
    frameMedian > quantile(frameMedian,0.75)+10*iqr(frameMedian));
tstamp = false(videoDims(4),1);
tstamp(tInd) = 1;
tstamp(tInd(1)-(1:-1:1))        = 1;                                        % Make sure to remove a frame before its too bright
tstamp(tInd(end)+(1:1))         = 1;                                        % Make sure to remove a frame after its too bright
tstamp(1:tInd(1)-10)            = 1;
if numel(tstamp) > numel(frsrs)
    tstamp = tstamp(1:numel(frsrs));
end
frsrs(tstamp)               = [];                                           % Remove frames that are too bright (equal to 1)
video(:,:,:,tstamp)         = [];                                           % Remove frames that are too bright (equal to 1)
videoDims                   = size(video);                                  % Get new video dimensions
clear vid capTime tEnd fStart counter frameTimeSeries frskip frameMedian tInd
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% VIDEO READER AND IMAGE LOADER BLOCK END %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%% IMAGE REGISTRATION BLOCK START  %%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% STEP 1 - USING SUB-SAMPLED ROI, TRY TO FIND EYE
rescaleFactor   = 4;                                                        % Rescaling factor to reduce resolution (speed-up processing)
eyeDetector     = vision.CascadeObjectDetector(...
    fullfile(pwd,'haarcascade_eye.xml'));
eyeDetector.MinSize         = ceil((1/4)*[min([videoDims(2) videoDims(1)]) ...
    min([videoDims(2) videoDims(1)])]/rescaleFactor);                       % Minimum threshold feature size
eyeDetector.MaxSize         = ceil([max([videoDims(2) videoDims(1)]) ...
    max([videoDims(2) videoDims(1)])]/rescaleFactor);                       % Maximum threshold feature size
eyeDetector.MergeThreshold  = 5;                                            % Set merge threshold between levels
rmVect      = false(videoDims(4),1);
for k = 1:videoDims(end)                                                    % Run Haar feature detector
    cur             = imresize(video(:,:,:,k),1/rescaleFactor);             % Grab current frame, resize
    tempEye         = step(eyeDetector,cur);                                % Run Haar detector
    [tempEye,~]     = sortrows(tempEye,3,'descend');                        % Sort Haar detector results to list largest region first
    if isempty(tempEye)
        rmVect(k)   = 1;
    end
end
frsrs(rmVect)       = [];                                                   % Remove frames that are too bright (equal to 1)
video(:,:,:,rmVect) = [];                                                   % Remove frames that are too bright (equal to 1)
videoDims           = size(video);                                          % Get new video dimensions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%% VIDEO READER AND IMAGE LOADER BLOCK END %%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%% IMAGE REGISTRATION BLOCK START  %%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%% Registration settings block %%%%%%%%%%%%%%%%%%%%%%%
NoOfWedges  = 180;                                                          % FMC operator number of wedges
MinRad      = 2;                                                            % FMC operator minimum radius
iter        = 0;
scale       = zeros([videoDims(4),1]);                                      % Preallocate scaling displacement                            % Cartesian grid
refImg      = double(imresize(rgb2gray(video(:,:,:,1)),1/rescaleFactor));   % Grab reference image, rescale
MaxRad      = min(size(refImg,1), size(refImg,2))/2;                        % FMC operator maximum radius
SpatialWindow   = gaussianWindowFilter(size(refImg),[0.5,0.5],'fraction');  % Spatial Apod Window
FMCWindow       = gaussianWindowFilter([NoOfWedges size(refImg,2)],...
    [0.5,0.5],'fraction');                                                  % FMC Apod Win
[xSub, ySub]    = meshgrid(-size(refImg,2)/2:1:(size(refImg,2)/2-1),...
    -size(refImg,1)/2:1:(size(refImg,1)/2-1));                              % Cartesian grid for reduced resolution
[XLP, YLP]      = LogPolarCoordinates([size(refImg,1),size(refImg,2)],...
    NoOfWedges, size(refImg,2), MinRad , MaxRad, 2*pi);                     % Log-Polar grid
while min(scale) < 1 && iter <= 1
    [~,refInd]      = min(scale);
    dispX           = zeros([videoDims(4),1]);                              % Preallocate horizontal (x-axis) displacement
    dispY           = zeros([videoDims(4),1]);                              % Preallocate vertical (y-axis) displacement
    dispS           = zeros([videoDims(4),1]);                              % Preallocate scaling displacement
    dispA           = zeros([videoDims(4),1]);                              % Preallocate angle displacement
    refImg          = double(imresize(rgb2gray(video(:,:,:,refInd(1))),1/rescaleFactor));  % Grab reference image, rescale
    refF  = griddedInterpolant(xSub',ySub',refImg','spline','none');        % Build reference frame interp Function
    %%%%%%%%%%%%%%%%%%%%%%%%%%% Registration Process %%%%%%%%%%%%%%%%%%%%%%
    for k = 1:videoDims(end)
        fprintf('Registering frame %03i of %03i ... \r',k,videoDims(end));
        curF    = griddedInterpolant(xSub',ySub',...
         double(imresize(rgb2gray(video(:,:,:,k)),1/rescaleFactor))','spline','none');% Build reference frame interp Function
        [dispX(k),dispY(k),dispS(k),dispA(k),~] = statisticalRegister(refF,curF,...
            SpatialWindow,FMCWindow,size(refImg,1),size(refImg,2),...
            MinRad,MaxRad,xSub,ySub,XLP,YLP,1E-4,100);                      % Run registration
    end    
    scale       = (MaxRad/MinRad).^(-dispS/size(refImg,2));                 % Convert scale
    angle       = 2*pi*dispA/size(XLP,1);                                   % Convert scale
    tstamp      = false(videoDims(4),1);
    tstamp(scale < 0.5 | scale > 2) = 1;
    tstamp(dispS < quantile(dispS,0.25) - 3*iqr(dispS) | ...
        dispS > quantile(dispS,0.75) + 3*iqr(dispS)) = 1;
%     tstamp(dispX < quantile(dispX,0.25) - 1.5*iqr(dispX) | ...
%         dispX > quantile(dispX,0.75) + 1.5*iqr(dispX)) = 1;
%     tstamp(dispY < quantile(dispY,0.25) - 1.5*iqr(dispY) | ...
%         dispY > quantile(dispY,0.75) + 1.5*iqr(dispY)) = 1;
    frsrs(tstamp) = [];
    scale(tstamp) = [];
    angle(tstamp) = [];
    dispX(tstamp) = [];
    dispY(tstamp) = [];
    video(:,:,:,tstamp) = [];
    videoDims   = size(video);
    iter        = iter + 1;
    %%%%%%%%%%%%%%%%%%%%%%%%%% Run Outlier Detection %%%%%%%%%%%%%%%%%%%%%%
end
clear XLP YLP NoOfWedges MinRad MaxRad dispS SpatialWindow FMCWindow
clear refF curF scaleThresh refImg k
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%% IMAGE REGISTRATION BLOCK END  %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%% HAAR EYE DETECTOR BLOCK START %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%% STEP 1 - USING SUB-SAMPLED ROI, TRY TO FIND EYE
storeEye     = zeros([videoDims(4),4]);                                     % Preallocate feature matrix
eyeDetector  = vision.CascadeObjectDetector(...
    fullfile(pwd,'haarcascade_eye.xml'));
eyeDetector.MinSize         = ceil((1/4)*[min([videoDims(2) videoDims(1)]) ...
    min([videoDims(2) videoDims(1)])]/rescaleFactor);                       % Minimum threshold feature size
eyeDetector.MaxSize         = ceil([max([videoDims(2) videoDims(1)]) ...
    max([videoDims(2) videoDims(1)])]/rescaleFactor);                       % Maximum threshold feature size
eyeDetector.MergeThreshold  = 5;                                            % Set merge threshold between levels
maxSubReg = zeros(ceil([videoDims(1) videoDims(2)]/rescaleFactor));
fprintf('Finding eye . . . \r')
for k = 1:videoDims(end)                                                    % Run Haar feature detector
    cur =  imresize(video(:,:,:,k),1/rescaleFactor);                        % Grab current frame, resize
    Tf = [scale(k)*cos(angle(k)) -scale(k)*sin(angle(k)) dispX(k);...
        scale(k)*sin(angle(k)) scale(k)*cos(angle(k)) dispY(k); 0 0 1];     % Construct current frame transform matrix
    for n = 1:3                                                             % Register Images
        curF = griddedInterpolant(xSub',ySub',...
            double(cur(:,:,n))','spline','none');
        cur(:,:,n) = uint8(tformImage(xSub,ySub,Tf,...
            [size(cur,1) size(cur,2)],curF));
    end
    cur(isnan(cur)) = 0;
    tempEye         = step(eyeDetector,cur);                                % Run Haar detector
    [tempEye,~]     = sortrows(tempEye,3,'descend');                        % Sort Haar detector results to list largest region first
    try
        storeEye(k,:)   = tempEye(1,:);                                     % Rescale Haar detector results
        ROI             = cur(tempEye(2)+(1:(tempEye(4)-1)),...
            tempEye(1)+(1:(tempEye(3)-1)),:);                               % Crop to eye, take image complement
        ROI             = rgb2hsl(double(ROI)/255);
        ROI(:,:,2)      = double(histeq(uint8(ROI(:,:,2)*255)))/255;
        ROI             = hsl2rgb(ROI)*255;
        roi             = imcomplement(uint8(max(ROI,[],3)));               % Filter current image with gaussian filter
        [~,indROI]      = max(roi(:));                                      % Find index of maximum from image
        [ycent,xcent]   = ind2sub(size(roi),indROI);                        % Go from index to subs
        storeEye(k,1)   = (0*xcent+tempEye(1)+storeEye(k,3)/2);             % Set new center X
        storeEye(k,2)   = (0*ycent+tempEye(2)+storeEye(k,4)/2);             % Set new center Y
        storeEye(k,3)   = storeEye(k,3)/2;
        storeEye(k,4)   = storeEye(k,4)/2;
    catch
        storeEye(k,1)   = nan;
        storeEye(k,2)   = nan;
        storeEye(k,3)   = nan;
        storeEye(k,4)   = nan;
    end
    if k == 1
        maxSubReg = double(cur)/videoDims(end);
    else
        maxSubReg = maxSubReg + double(cur)/videoDims(end);
    end
end
%%%%% STEP 2 - USING SUB-SAMPLED ROI, TRY TO "EXTRACT" PUPIL, DETERMINE A
%%%%% BETTER WINDOW SIZE (DYNAMICALLY)
%%%%% STEP 3 - REGISTER FRAMES IN MEMORY
%%%
scaleFactor = 2;
xcent       = round(rescaleFactor/scaleFactor*nanmedian(storeEye(:,1)));        % Update eye center x-position
ycent       = round(rescaleFactor/scaleFactor*nanmedian(storeEye(:,2)));        % Update eye center y-position
winSize     = ceil(rescaleFactor/scaleFactor*1*nanmedian(nanmedian(storeEye(:,3:4),1),2));% Subregion window size from Haar detector
dispX = dispX*rescaleFactor/scaleFactor;                                    % Rescale registration x-position
dispY = dispY*rescaleFactor/scaleFactor;                                    % Rescale registration y-position
current  = double(imresize(video(:,:,:,1),1/scaleFactor));
videoStack = zeros([size(current,1) size(current,2) videoDims(3) videoDims(4)]);
[XCart, YCart]  = meshgrid(-size(current,2)/2:1:(size(current,2)/2-1),...
        -size(current,1)/2:1:(size(current,1)/2-1));                        % Cartesian grid
for k = 1:videoDims(4)
    fprintf('Registering frame to memory: %03i of %03i ... \r',k,videoDims(4));
    tform   = [scale(k)*cos(angle(k)) -scale(k)*sin(angle(k)) dispX(k);...
        scale(k)*sin(angle(k)) scale(k)*cos(angle(k)) dispY(k); 0 0 1];     % Set reference transform matrix
    current = double(imresize(video(:,:,:,k),1/scaleFactor));               % Get current image
    figure(11);
    subplot(1,2,1);
    imagesc(uint8(current)); axis off; axis image;
    title('Video Frame','FontSize',24','FontWeight','bold');
    for kk = 1:3
        curF    = griddedInterpolant(XCart',YCart',current(:,:,kk)','spline','none');
        current(:,:,kk)   = tformImage(XCart,YCart,tform,...
            [size(current,1) size(current,2)],curF);                        % Register current
    end
    current(isnan(current)) = 0; current(current < 0) = 0; current(current > 255) = 255;
    subplot(1,2,2);
    imagesc(uint8(current)); axis off; axis image;
    title('Registered Frame','FontSize',24','FontWeight','bold');
    set(gcf,'Position',[300 10 600 600]);
    pause(1E-3);
    videoStack(:,:,:,k) = uint8(current);
end
close(11)
video       = videoStack;
videoDims   = size(videoStack);
clear ref cur roi eyeDetector curF tempEye k n ROI indROI Tf videoStack
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%% HAAR EYE DETECTOR BLOCK END %%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%% PUPIL DILATION START %%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%% Correlation settings block %%%%%%%%%%%%%%%%%%%%%%%%
[xCart,yCart]       = meshgrid(((-(winSize-1)/2):1:((winSize-1)/2)),...
    ((-(winSize-1)/2):1:((winSize-1)/2)));                                  % Cartesian Grid
ROI             = rgb2hsl(double(video(round(yCart(:,1)+ycent),...
    round(xCart(1,:)+xcent),:,1))/255);                                     % Convert from RGB to HSL
ROI(:,:,3)      = double(histeq(uint8(ROI(:,:,3)*255)))/255;                % Equalize saturation
ROI(:,:,2)      = double(histeq(uint8(ROI(:,:,2)*255)))/255;                % Equalize saturation
ROI             = hsl2rgb(ROI)*255;
figure(101);
imagesc(uint8(ROI)); 
axis image; axis off;
[xLocs,yLocs] = getpts(gcf);
xCP   = (max(xLocs)+min(xLocs))/2; 
yCP   = (max(yLocs)+min(yLocs))/2;
xcent = xcent + round(xCP-winSize/2);
ycent = ycent + round(yCP-winSize/2);
winsize = 4*round(max(sqrt((xLocs-xCP).^2+(yLocs-yCP).^2)));
if mod(winsize,2) ~= 0
    winsize = winsize + 1;
end
if isnan(winsize)
    winsize = 180;
end
[xCart,yCart]       = meshgrid(((-(winsize-1)/2):1:((winsize-1)/2)),...
    ((-(winsize-1)/2):1:((winsize-1)/2)));                                  % Cartesian Grid
dilateMinRad        = 1;                                                    % Dilation FMC minimum radius
dilateMaxRad        = winsize/2;                                            % Dilation FMC maximum radius
dilateNoOfWedges    = 360;                                                  % Dilation FMC number of wedges
[xLP,yLP]           = LogPolarCoordinates([winsize, winsize],...
    dilateNoOfWedges, winsize, dilateMinRad , dilateMaxRad, 2*pi);          % Polar Grid
dilateSptWindowSCC  = gaussianWindowFilter([winsize winsize],...
    [0.5 0.5],'fraction');                                                  % Spatial Apod Window
dilateFMCWindowSCC  = gaussianWindowFilter([dilateNoOfWedges winsize],...
    [0.5 0.5],'fraction');                                                  % FMC Apod Win
dispSInst      = zeros([videoDims(4),1]);                                   % Preallocate dilation velocity
dispxInst      = zeros([videoDims(4),1]);                                   % Preallocate dilation velocity
dispyInst      = zeros([videoDims(4),1]);                                   % Preallocate dilation velocity
tVect = [frsrs(3:end)-(frsrs(:,3:end)-frsrs(:,1:end-2))/2-1 ...
    frsrs(end)-1]/deltaTime;                                                % Time vector for scale
tStep = [2 (frsrs(:,3:end)-frsrs(:,1:end-2)) 2]/2;                          % Time vector for integration
%%%%%%%%%%%%%%%%%%%%%%%%%%% Correlation Process %%%%%%%%%%%%%%%%%%%%%%%%%%%
for k = 2:(videoDims(4)-1)
    %%%%%%%%%%%%%%%%%%%% Dilation estimate by pair-wise correlation %%%%%%%
    fprintf('Frame-to-Frame correlation: %03i of %03i ... \r',k,videoDims(4)-1);
    reference   = double(video(:,:,:,k-1));                                 % Get reference image
    current     = double(video(:,:,:,k+1));                                 % Get current image
    [dispSInst(k),dispxInst(k),dispyInst(k)] =  dilationEstimator(...
        reference,current,videoDims,XCart,YCart,xCart,yCart,xcent,ycent,...
        xLP,yLP,dilateSptWindowSCC,dilateFMCWindowSCC,...
        dilateMinRad,dilateMaxRad,winsize,1E-5,250);
    dispSInst(k)    = dispSInst(k)/(2*tStep(k));                            % Scale Displacement based on Frame Step
    
    refROI          = rgb2hsl(double(video(round(yCart(:,1)+ycent),...
        round(xCart(1,:)+xcent),:,1))/255);                                     % Convert from RGB to HSL
    refROI(:,:,3)      = double(histeq(uint8(refROI(:,:,3)*255)))/255;                % Equalize saturation
    refROI(:,:,2)      = double(histeq(uint8(refROI(:,:,2)*255)))/255;                % Equalize saturation
    refROI             = hsl2rgb(refROI)*255;
    
    curROI          = rgb2hsl(double(video(round(yCart(:,1)+ycent),...
        round(xCart(1,:)+xcent),:,k))/255);                                     % Convert from RGB to HSL
    curROI(:,:,3)      = double(histeq(uint8(curROI(:,:,3)*255)))/255;                % Equalize saturation
    curROI(:,:,2)      = double(histeq(uint8(curROI(:,:,2)*255)))/255;                % Equalize saturation
    curROI             = hsl2rgb(curROI)*255;
%     imwrite(uint8(curROI),sprintf('/Users/brettmeyers/Desktop/demo+eye/frame_%03i.tiff',k-1),'tiff','compression','none');
%     imwrite(uint8(rgb2gray(uint8(curROI))),sprintf('/Users/brettmeyers/Desktop/demo+eye/gray_%03i.tiff',k-1),'tiff','compression','none');
    
    figure(11);
    subplot(1,5,1);
    imagesc(uint8(refROI)); axis off; axis image;
    title('Reference Frame');
    subplot(1,5,2);
    imagesc(uint8(curROI)); axis off; axis image;
    title('Instantaneous Frame');
    subplot(1,5,4:5);
    plot((frsrs(1:k)-frsrs(1))/deltaTime,-dispSInst(1:k)*scaleFactor,'o-','Color',[0 0 0],'MarkerFaceColor',[1 0 0],'LineWidth',2); 
    axis([0 (frsrs(end)-frsrs(1))/deltaTime -3 3]);
    grid on;
    xlabel('Frame Time, s');
    ylabel('Pupil Displacement, pix/fr');
    set(gca,'LineWidth',2,'FontSize',24,'FontWeight','bold');
    set(gcf,'Position',[150 250 1200 350]);
    pause(1E-3);
end
% close(11)
dMaxOri = dilateMaxRad;
dispSOri= dispSInst;
wSizeOri= winsize;
clear xLP yLP dilateFMCWindow dilateSpatialWindow dilateNoOfWedges
clear current reference T1 T2 refF curF refIM curIM fr01F fr02F
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%% PUPIL DILATION END %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%% RHEOLOGICAL MODEL OF IRIS MOTION FITTING START %%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dilateMaxRad    = dMaxOri*scaleFactor;
dispSInst       = dispSOri*scaleFactor;
winsize         = wSizeOri*scaleFactor;
tVect           = tVect-tVect(1);
tspan           = min(tVect(:)):1/deltaTime:max(tVect(:));                      % Generate linearly spaced time series
if numel(tVect) < numel(dispSInst)
    dispSInst = dispSInst(1:numel(tVect));
end
% % tstamp = isoutlier(dispSInst(:),'movmedian',9,'ThresholdFactor',3);% | 
% tstamp = isoutlier(dispSInst(:),'quartiles','ThresholdFactor',5);
% for n = 1:numel(tstamp)
%     if tstamp(n) == 1
%         tvals = abs(tVect(n) - tVect);
%         inds = 1:numel(tVect);
%         [~,sind] = sort(tvals,'ascend');
%         inds = inds(sind);
%         dispSInst(n) = median(dispSInst(inds(2:9)));
%     end
% end
% tstamp = isoutlier(dispSInst(:),'movmedian',9,'ThresholdFactor',3);% | isoutlier(dispSInst(:),'quartiles','ThresholdFactor',6);
% for n = 1:numel(tstamp)
%     if tstamp(n) == 1
%         tvals = abs(tVect(n) - tVect);
%         inds = 1:numel(tVect);
%         [~,sind] = sort(tvals,'ascend');
%         inds = inds(sind);
%         dispSInst(n) = median(dispSInst(inds(2:9)));
%     end
% end
dilateVel   = interp1(tVect,dispSInst(:),tspan,'pchip');  
dilationRaw = (dilateMaxRad/dilateMinRad).^...
    (-cumsum(dilateVel(:),1)/(winsize/2));                                  % Compute dilation through dilation rate integration
% Set initial fit paramaters for rheological model (Fan & Yao, 2010)
%   Kc  - Iris constrictor elastic constant
%   Kd  - Iris dilator elastic constant
%   nu  - Iris viscosity constant
Kc = 0.0536*1; Kd = 1.0829*1; nu = 3.2583*1; l0 = 0.25; L0 = 1.0;
dilatVelCur     = (1-(dilateMaxRad/dilateMinRad).^(dilateVel(:)/(winsize/2)))/mean(diff(tspan(:))); % Initialize current dilation rate series for nLSQ model fitting
dilatVelPrev    = zeros(size(dilatVelCur));                                 % Initialize previous dilation rate series for nLSQ model fitting
iterations      = 1;                                                        % Initialize iteration number for while loop processing
% Run iterative rheological model fitting on dilation and dilation rate
% time series data. During the while loop iteration 
%   (1) current dilation rate data is smoothed using a Fourier low pass filter 
%   (2) current dilation after smoothing is calculated
%   (3) approximations for dilation acceleration and the stimulus forcing
%       function are obtained
%   (4) nLSQ fitting is performed on the raw, interpolated dilation rate
%       and dilation with a smooth forcing function
%   (5) Fit parameters are updated from the nLSQ
%   (6) current dilation rate data is updated from the nLSQ output
% Loop stops once the RMS for dilation rate has minimized OR the number of
% iterations passes 5 (need a stopping criteria so loop doesn't over-smooth
while rms(abs(dilatVelCur(:)-dilatVelPrev(:)),1) > 1E-2 && iterations <= 1
    dilatVelCur     = smoothdata(dilatVelCur,'movmean',5);
%     dilationCur     = 1+cumtrapz(tspan,dilatVelCur);
    dilationCur     = dilationRaw;
    dilatAccCur     = socdiff(dilatVelCur,1/deltaTime,1);                   % Approximate the dilation acceleration
    forceFunc       = (dilatAccCur(:) + Kc*(0.25-dilationCur).^2 -...
        Kd*(1.00-dilationCur).^2 + nu*dilatVelCur(:));                      % Approximate the stimulus forcing function from the rheological model
    forceFunc       = forceFunc - forceFunc(1);                             % Correct for bias at first index
    soln = [dilationRaw(:), -dilateVel(:)];                                 % Initialize ydata for nLSQ using raw dilation and dilation rate 
    xt0  = [1, 0, Kc, Kd, nu, l0, L0];                                      % Initialize fitting parameters xdata
%     options = optimoptions('lsqcurvefit','Algorithm',...
%         'trust-region-reflective','Display','off',...
%         'MaxIterations',400,'MaxFunctionEvaluations',500);                  % Set nLSQ options (tweaking might speed things up)
    options = optimoptions('lsqcurvefit','Algorithm',...
        'trust-region-reflective','Display','off',...
        'MaxIterations',10,'MaxFunctionEvaluations',10);                  % Set nLSQ options (tweaking might speed things up)
    lb = [1.00 0.00 1E-3*Kc 1E-3*Kd 1E-3*nu 0.25 0.25];                                  % Set lower bound (ensures dilation and dilation rate first index are constant)
    ub = [1.00 0.00 1E+3*Kc 1E+3*Kd 1E+3*nu 1    1   ];                                  % Set upper bound (ensures dilation and dilation rate first index are constant)
    try
    [ pbest, ~, presidual, ~, ~] = lsqcurvefit(@(t,x)...
        PLRModel(t,x,forceFunc),xt0,tspan(:),soln,lb,ub,options);           % Perform nLSQ data fitting for rheological model onto raw data
    catch
        pbest = xt0;
        presidual = zeros(size(soln));
    end
    dilatVelCur = -dilateVel(:)+presidual(:,2);                             % Update current dilation rate from model fit
    Kc  = pbest(3); Kd  = pbest(4); nu = pbest(5);                          % Update fitting parameters
    l0  = pbest(6); L0  = pbest(7); 
    iterations  = iterations + 1;                                           % Update iteration number
end
dilationInst    = dilationRaw(:) + presidual(:,1);                          % Update dilation from model fit
dilateVelInst   = dilateVel(:)- presidual(:,2);                             % Update current dilation rate from model fit
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%% RHEOLOGICAL MODEL OF IRIS MOTION FITTING END %%%%%%%%%%%%%%%
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%% PLOT TIMESERIES DATA FOR DILATION AND DILATION RATE %%%%%%%%%%%%
figure(1);
subplot(2,1,1)
plot(tspan,dilateVelInst.*2,'LineWidth',2);
hold on;
plot(tspan,dilateVel.*2,'LineWidth',2);
hold off;
grid on;
axis([0 5 -5 5]);
set(gca,'LineWidth',2,'FontSize',18,'FontWeight','bold');
xlabel('Time, seconds','FontSize',18,'FontWeight','bold');
ylabel('Dilatation Velocity, ppf','FontSize',18,'FontWeight','bold');

subplot(2,1,2)
plot(tspan,dilationInst*100,'LineWidth',2);
hold on;
plot(tspan,dilationRaw*100,'LineWidth',2);
hold off;
axis([0 5 0 150]);
grid on;
set(gca,'LineWidth',2,'FontSize',18,'FontWeight','bold');
xlabel('Time, seconds','FontSize',18,'FontWeight','bold');
ylabel('Dilatation, percent','FontSize',18,'FontWeight','bold');
set(gcf,'Position',[100 100 400 550],'Color',[1 1 1]);
print(gcf,fullfile(pathName,[fileBase, '_timeseries_plot.png']),'-dpng','-r0');
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%% TIME SERIES ANALYSIS START %%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
refImg          = video(round(yCart(:,1)+ycent),...
    round(xCart(1,:)+xcent),:,refInd);                                      % Crop to only the eye
refImg          = rgb2hsl(double(refImg)/255);
refImg(:,:,2)   = double(histeq(uint8(refImg(:,:,2)*255)))/255;
refImg(:,:,3)   = double(histeq(uint8(refImg(:,:,3)*255)))/255;
refImg          = hsl2rgb(refImg)*255;
refImg          = imcomplement(histeq(uint8(max(imfilter(refImg,...
    fspecial('gaussian',[13 13],3),255),[],3))));
pupilProps      = regionprops(bwselect(imbinarize(refImg,0.9),...
    size(refImg,1)/2,size(refImg,2)/2),...
    'EquivDiameter','MajorAxisLength','MinorAxisLength');                   % Use regionprops to estimate pupil diameter
if isempty(pupilProps)
    pupilDiam = nan;
else
for k = 1:numel(pupilProps)
    if k == 1
        pupilDiam = pupilProps(k).EquivDiameter;                            % Store pupil diameter
    else
        pupilDiam = max(pupilDiam,pupilProps(k).EquivDiameter);             % Store maximum value to pupil diameter
    end
end
end
pixeltomm       = (rescaleFactor*nanmedian(storeEye(:,end)))/24;            % Use Biometrics to get physical units of dilation
approxPupilDia  = (pupilDiam)/pixeltomm;                                    % Physical approximate pupil diameter
dilation        = dilationInst * approxPupilDia;                            % Dimensionalize for physical dilation
dispSInstval = 1-(dilateMaxRad/dilateMinRad).^...
        ((-dilateVelInst(:).*2)/(winsize));
dilateVelRaw = 1-(dilateMaxRad/dilateMinRad).^...
        ((-dilateVel(:).*2)/(winsize));
dilateVelVal = 1-(dilateMaxRad/dilateMinRad).^...
        ((-dilateVelInst(:).*2)/(winsize));
fid = fopen(fullfile(pathName,...
    [fileBase,'_timeseries_measurements.csv']),'w');                        % Open Text File
cHeader = {'Time(s)' 'Dilation Ratio Inst' 'Pupil Diameter Inst' ...
    'Raw Velocity Inst' 'Dimensional Velocity Inst'}; %dummy header
commaHeader = [cHeader;repmat({','},1,numel(cHeader))]; %insert commaas
commaHeader = commaHeader(:)';
textHeader = cell2mat(commaHeader); %cHeader in text with commas
fprintf(fid,'%s\n',textHeader);             % Specify Headers
fprintf(fid, '%f,%f,%f,%f,%f \n', [tspan(:) ...
    dilationInst(:) dilation(:) dilateVelInst(:) dispSInstval(:)]');     % Print Results
fclose(fid);                                                                % Close Text File

fid = fopen(fullfile(pathName,...
    [fileBase,'_raw_vs_validated_measurements.csv']),'w');                  % Open Text File
cHeader = {'Time(s)' 'Dilation Ratio Raw' 'Dilation Ratio Val' ...
    'Raw Velocity Inst' 'Val Velocity Inst'}; %dummy header
commaHeader = [cHeader;repmat({','},1,numel(cHeader))]; %insert commaas
commaHeader = commaHeader(:)';
textHeader = cell2mat(commaHeader); %cHeader in text with commas
fprintf(fid,'%s\n',textHeader);             % Specify Headers
fprintf(fid, '%f,%f,%f,%f,%f \n', [tspan(:) ...
    dilationRaw(:) dilationInst(:) dilateVelRaw(:) dilateVelVal(:)]');        % Print Results
fclose(fid);

locSearchInd        = find(tspan <= 2.5);
[~,constrictInd]    = min(dilationRaw(1:locSearchInd(end)));
maxConstrictTime    = tspan(constrictInd);
[pks,locs]          = max((socdiff(dilateVelInst(1:constrictInd),1,1)));
quant50ind          = find(pks >= median(pks));
onsetInd            = locs(quant50ind(1));
onsetTime           = tspan(onsetInd);
recoveryInd         = find(dilationRaw(constrictInd:end) >=...
    0.75*abs(dilationRaw(onsetInd-1)-dilationRaw(constrictInd))+...
    dilationRaw(constrictInd));
if isempty(recoveryInd)
    recoveryInd     = find(dilationRaw(constrictInd:end) == ...
        max(dilationRaw(constrictInd:end)));
    recoveryInd     = recoveryInd + constrictInd - 1;
    recoveryTime    = tspan(recoveryInd(1));
else
    recoveryInd     = recoveryInd + constrictInd;
    recoveryTime    = tspan(recoveryInd(1));
end
averageConstriction = mean(dilateVelRaw(onsetInd:constrictInd))*100;
averageDilation     = mean(dilateVelRaw((constrictInd+1):recoveryInd(1)))*100;
fid = fopen(fullfile(pathName,...
    [fileBase,'_timeseries_parameters_raw.csv']),'w');                      % Open Text File
cHeader = {'Onset Time (s)' 'Peak Time (s)' 'Max Ratio' ...
'Recovery Time (s)' 'Constriction Velocity','Dilation Velocity'}; %dummy header
commaHeader = [cHeader;repmat({','},1,numel(cHeader))]; %insert commaas
commaHeader = commaHeader(:)';
textHeader = cell2mat(commaHeader); %cHeader in text with commas
fprintf(fid,'%s\n',textHeader);
fprintf(fid,'%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,\n', [onsetTime maxConstrictTime ...
    (1-dilationRaw(constrictInd))*100 recoveryTime ...
    averageConstriction(1) averageDilation(1)]');                       % Print Results
fclose(fid);                                                            % Close Text File

try
    locSearchInd        = find(tspan <= 2.5);
    [~,constrictInd]    = min(dilationInst(1:locSearchInd(end)));
    maxConstrictTime    = tspan(constrictInd);
    [pks,locs]          = max((socdiff(dilateVelInst(1:constrictInd),1,1)));
    quant50ind          = find(pks >= median(pks));
    onsetInd            = locs(quant50ind(1));
    onsetTime           = tspan(onsetInd);
    recoveryInd         = find(dilationInst(constrictInd:end) >=...
        0.75*abs(dilationInst(onsetInd-1)-dilationInst(constrictInd))+...
        dilationInst(constrictInd));
    if isempty(recoveryInd)
        recoveryInd     = find(dilationInst(constrictInd:end) == ...
            max(dilationInst(constrictInd:end)));
        recoveryInd     = recoveryInd + constrictInd - 1;
        recoveryTime    = tspan(recoveryInd(1));
    else
        recoveryInd     = recoveryInd + constrictInd;
        recoveryTime    = tspan(recoveryInd(1));
    end
    averageConstriction = mean(dispSInstval(onsetInd:constrictInd))*100;
    averageDilation     = mean(dispSInstval((constrictInd+1):recoveryInd(1)))*100;
    fid = fopen(fullfile(pathName,...
        [fileBase,'_timeseries_parameters_inst.csv']),'w');                      % Open Text File
    cHeader = {'Onset Time (s)' 'Peak Time (s)' 'Max Ratio' ...
    'Recovery Time (s)' 'Constriction Velocity','Dilation Velocity'}; %dummy header
    commaHeader = [cHeader;repmat({','},1,numel(cHeader))]; %insert commaas
    commaHeader = commaHeader(:)';
    textHeader = cell2mat(commaHeader); %cHeader in text with commas
    fprintf(fid,'%s\n',textHeader);
    fprintf(fid,'%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,\n', [onsetTime maxConstrictTime ...
        (1-dilationInst(constrictInd))*100 recoveryTime ...
        averageConstriction(1) averageDilation(1)]');                       % Print Results
    fclose(fid);                                                            % Close Text File
    
catch
    fid = fopen(fullfile(pathName,...
        [fileBase,'_timeseries_parameters_inst.csv']),'w');                      % Open Text File
    cHeader = {'Onset Time (s)' 'Peak Time (s)' 'Max Ratio' ...
    'Recovery Time (s)' 'Constriction Velocity','Dilation Velocity'}; %dummy header
    commaHeader = [cHeader;repmat({','},1,numel(cHeader))]; %insert commaas
    commaHeader = commaHeader(:)';
    textHeader = cell2mat(commaHeader); %cHeader in text with commas
    fprintf(fid,'%s\n',textHeader);
%     fprintf(fid, [ 'Onset Time,s' ' ' 'Peak Time,s' ' '...
%         'Max Ratio' ' ' ' Recovery Time,s' ' '...
%         'Constriction Velocity' ' ' 'Dilation Velocity' '\n']);             % Specify Headers
    fprintf(fid,'%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,%03.3f,\n', [nan(1,1) nan(1,1) ...
        nan(1,1) nan(1,1) nan(1,1) nan(1,1)]');                             % Print Results
    fclose(fid);
end
toc
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%% TIME SERIES ANALYSIS END %%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
end
%%
function [dispX,dispY,dispS,dispA,iteration] =  statisticalRegister(refF,curF,...
    SptWindow,FMCWindow,height,width,MinRad,MaxRad,...
    xCart,yCart,xLP,yLP,err_thresh,iteration_thresh)
% FUNCTION FOR REGISTRATION OF SINGLE COLOR CHANNEL FROM IMAGE PAIR
err = inf; iteration= 1;                                                    % Initialize Error & Iterations
dispX = 0; dispY = 0; dispS = 0; dispA = 0;                                 % Initialize displacements & scale
TRev = eye(3); TFor = eye(3);                                               % Initialize Image Transform Matrices
% Run iterative registration
while err >= err_thresh && iteration <= iteration_thresh
    % Reconstruct images based on transform matrices
    fr01    = tformImage(xCart,yCart,TFor,[height width],curF);
    fr02    = tformImage(xCart,yCart,TRev,[height width],refF);
    fr01(isnan(fr01)) = 0; fr02(isnan(fr02)) = 0;
    % Calculate FFTs for image pair
    FFT01   = fft2(SptWindow.*(fr01-mean(fr01(:))));
    FFT02   = fft2(SptWindow.*(fr02-mean(fr02(:))));
    if mod(size(FFT01,2),2) == 0
        FMC01 = fft2(FMCWindow.*interp2(fftshift(SptWindow.*abs(FFT01)),xLP+0.5,yLP+0.5,'spline'));
        FMC02 = fft2(FMCWindow.*interp2(fftshift(SptWindow.*abs(FFT02)),xLP+0.5,yLP+0.5,'spline'));
    else
        FMC01 = fft2(FMCWindow.*interp2(fftshift(SptWindow.*abs(FFT01)),xLP+0.0,yLP+0.5,'spline'));
        FMC02 = fft2(FMCWindow.*interp2(fftshift(SptWindow.*abs(FFT02)),xLP+0.0,yLP+0.5,'spline'));
    end
    % Perform displacement-based cross-correlation
    dispSpectral    = FFT01.*conj(FFT02);                                   % Do Standard Cross-Correlation
%     [plX,plY,~,~,~,~,~,~] = subpixel(abs(fftshift(ifft2(dispSpectral))),...
%         size(dispSpectral,2),size(dispSpectral,1),ones(size(dispSpectral)),1,1,[3, 3]);
    [plX,plY,~,~,~,~] = subpix3PtFit(abs(fftshift(ifft2(dispSpectral))),...
        size(dispSpectral,2),size(dispSpectral,1),ones(size(dispSpectral)));  
    dispX           = dispX - plX(1);
    dispY           = dispY - plY(1);
    % Perform scaling-based cross-correlation
    fmcSpectral     = FMC01.*conj(FMC02);                                   % Do Standard Cross-Correlation
%     [fmcLocX,fmcLocY,~,~,~,~,~,~] = subpixel(abs(fftshift(ifft2(fmcSpectral))),...
%         size(fmcSpectral,2),size(fmcSpectral,1),ones(size(fmcSpectral)),1,1,[3, 3]);
    [fmcLocX,fmcLocY,~,~,~,~] = subpix3PtFit(abs(fftshift(ifft2(fmcSpectral))),...
        size(fmcSpectral,2),size(fmcSpectral,1),ones(size(fmcSpectral)));
    dispS           = dispS - fmcLocX(1);
    dispA           = dispA - fmcLocY(1);
    scale           = (MaxRad/MinRad)^(-dispS/width);
    angle           = 2*pi*dispA/size(xLP,1);
    % Update Error and Iterations
    err             = max(sqrt(plX(1).^2+plY(1).^2),abs(fmcLocX(1)));
    iteration       = iteration + 1;
    % Update Transform Matrices
    TRev(1,1)       =  sqrt(1/scale)*cos(-angle/2); 
    TRev(2,2)       =  sqrt(1/scale)*cos(-angle/2);
    TRev(1,2)       = -sqrt(1/scale)*sin(-angle/2); 
    TRev(2,1)       =  sqrt(1/scale)*sin(-angle/2);
    TRev(1,3)       = -dispX/2;       
    TRev(2,3)       = -dispY/2;
    TFor(1,1)       =  sqrt(1*scale)*cos( angle/2); 
    TFor(2,2)       =  sqrt(1*scale)*cos( angle/2);
    TFor(1,2)       = -sqrt(1*scale)*sin( angle/2);  
    TFor(2,1)       =  sqrt(1*scale)*sin( angle/2);
    TFor(1,3)       =  dispX/2;       
    TFor(2,3)       =  dispY/2;
end
end

function [dispS,dispX,dispY] =  dilationEstimator(refIM,curIM,videoDims,...
    XCart,YCart,xCart,yCart,xcent,ycent,xLP,yLP,SptWindow,FMCWindow,...
    MinRad,MaxRad,winsize,err_thresh,iteration_thresh)
%%%%%% PUPIL DILATION BLOCK START %%%%%
err   = Inf; iteration= 1;                                                  % Initialize Error & Iterations
TRev  = eye(3); TFor = eye(3);
dispX = 0; dispY = 0; dispS = 0; dispA = 0;                                 % Initialize disp & scale
ref = zeros(winsize,winsize,3); cur = zeros(winsize,winsize,3);
for kk = 1:3
    % Build interpolant function
    fr01F = griddedInterpolant(XCart',YCart',refIM(:,:,kk)','spline','none');
    fr02F = griddedInterpolant(XCart',YCart',curIM(:,:,kk)','spline','none');
    % Reconstruct images based on transform matrices AND
    % Do cropping + histogram equalization + complement of image
    ref(:,:,kk)  = tformImage(xCart+(xcent-videoDims(2)/2),...
        yCart+(ycent-videoDims(1)/2),TFor,size(yCart),fr01F); % Register reference
    cur(:,:,kk)  = tformImage(xCart+(xcent-videoDims(2)/2),...
        yCart+(ycent-videoDims(1)/2),TRev,size(yCart),fr02F); % Register reference
end
ref(isnan(ref)) = 0;  cur(isnan(cur)) = 0;
ref(ref < 0) = 0;     cur(cur < 0) = 0;
ref(ref > 255) = 255; cur(cur > 255) = 255;
% Convert reference to HSL, Equalize L, convert to RGB
ref = rgb2hsl(double(ref)/255);                                             % Get reference image
ref(:,:,3) = double(histeq(uint8(ref(:,:,3)*255)))/255;
ref(:,:,2) = double(histeq(uint8(ref(:,:,2)*255)))/255;
ref = uint8(hsl2rgb(ref)*255);
ref = (double(imcomplement(uint8(max(ref,[],3)))));

% ref = double(imcomplement(uint8(ref(:,:,3))));                              % Reference subregion

% Convert current to HSL, Equalize L, convert to RGB
cur = rgb2hsl(double(cur)/255);                                             % Get reference image
cur(:,:,3) = double(histeq(uint8(cur(:,:,3)*255)))/255;
cur(:,:,2) = double(histeq(uint8(cur(:,:,2)*255)))/255;
cur = uint8(hsl2rgb(cur)*255);
cur = (double(imcomplement(uint8(max(cur,[],3)))));

% cur = double(imcomplement(uint8(cur(:,:,3))));                              % Reference subregion

meanVal = mean([mean(ref(:)),mean(cur(:))]);
ref = double(255*(ref-meanVal)/(max(ref(:))-meanVal));
% ref = double(255*(ref-mean(ref(:)))/(max(ref(:))-mean(ref(:))));
ref(ref<0) = 0;
cur = double(255*(cur-meanVal)/(max(cur(:))-meanVal));
% cur = double(255*(cur-mean(cur(:)))/(max(cur(:))-mean(cur(:))));
cur(cur<0) = 0;
% Build interpolant function
fr01F = griddedInterpolant(xCart',yCart',ref','spline','none');
fr02F = griddedInterpolant(xCart',yCart',cur','spline','none');
while err >= err_thresh && iteration <= iteration_thresh
    % Reconstruct images based on transform matrices AND
    % Do cropping + histogram equalization + complement of image
    fr01  = tformImage(xCart,yCart,TFor,size(yCart),fr01F);                 % Register reference
    fr02  = tformImage(xCart,yCart,TRev,size(yCart),fr02F);                 % Register reference
    fr01(isnan(fr01)) = 0; fr01(fr01 < 0) = 0; fr01(fr01 > 255) = 255; 
    fr02(isnan(fr02)) = 0; fr02(fr02 < 0) = 0; fr02(fr02 > 255) = 255;
    % Calculate FFTs and perform image pair displacement cross-correlation
    FFT01           = fftshift(fft2(SptWindow.*(fr01-mean(fr01(:)))));
    FFT02           = fftshift(fft2(SptWindow.*(fr02-mean(fr02(:)))));
    dispSpectral    = FFT01.*conj(FFT02);
    % Run Fourier-Mellin Transform on FFTs
    if mod(size(FFT01,2),2) == 0
        FMC01 = fft2(FMCWindow.*interp2((1.*abs(FFT01)),xLP+0.5,yLP+0.5,'spline'));
        FMC02 = fft2(FMCWindow.*interp2((1.*abs(FFT02)),xLP+0.5,yLP+0.5,'spline'));
    else
        FMC01 = fft2(FMCWindow.*interp2((1.*abs(FFT01)),xLP+0.0,yLP+0.5,'spline'));
        FMC02 = fft2(FMCWindow.*interp2((1.*abs(FFT02)),xLP+0.0,yLP+0.5,'spline'));
    end
    fmcSpectral     = FMC01.*conj(FMC02);
%     [~,~,~,~,dx,dy,~,~] = subpixel(abs(fftshift(ifft2(fmcSpectral.*conj(fmcSpectral)))),...
%         size(fmcSpectral,2),size(fmcSpectral,1),ones(size(fmcSpectral)),3,1,[3, 3]);
%     rpcFilter      = energyfilt(size(fmcSpectral,2),size(fmcSpectral,1),[dy(1)/sqrt(2) dx(1)/sqrt(2)]);
%     [fmcSpectral, ~] = split_complex(fmcSpectral);
%     fmcSpectral     = rpcFilter.*fmcPhase;
%     [plX,plY,~,~,~,~,~,~] = subpixel(abs(fftshift(ifft2(dispSpectral))),...
%         size(dispSpectral,2),size(dispSpectral,1),ones(size(dispSpectral)),1,1,[3, 3]);
%     [fmcLocX,fmcLocY,~,~,~,~,~,~] = subpixel(abs(fftshift(ifft2(fmcSpectral))),...
%             size(fmcSpectral,2),size(fmcSpectral,1),ones(size(fmcSpectral)),1,0,[3, 3]);
    [plX,plY,~,~,~,~] = subpix3PtFit(abs(fftshift(ifft2(dispSpectral))),...
        size(dispSpectral,2),size(dispSpectral,1),ones(size(dispSpectral)));    
    [fmcLocX,fmcLocY,~,~,~,~] = subpix3PtFit(abs(fftshift(ifft2(fmcSpectral))),...
        size(fmcSpectral,2),size(fmcSpectral,1),ones(size(fmcSpectral)));
        
    dispX = dispX - 1*plX(1);   dispY = dispY - 1*plY(1);    
    dispS = dispS - fmcLocX(1); dispA = dispA - 0*fmcLocY(1);
    scale = (MaxRad/MinRad)^(-dispS/winsize);
    angle = 2*pi*dispA/size(xLP,1);
    % Update Error and Iterations
    err   = abs(fmcLocX(1));
    iteration       = iteration + 1;
    % Update Transform Matrices
    TRev(1,1)       =  sqrt(1/scale)*cos(-angle/2); 
    TRev(2,2)       =  sqrt(1/scale)*cos(-angle/2);
    TRev(1,2)       = -sqrt(1/scale)*sin(-angle/2); 
    TRev(2,1)       =  sqrt(1/scale)*sin(-angle/2);
    TRev(1,3)       = -dispX/2;       
    TRev(2,3)       = -dispY/2;
    TFor(1,1)       =  sqrt(1*scale)*cos( angle/2); 
    TFor(2,2)       =  sqrt(1*scale)*cos( angle/2);
    TFor(1,2)       = -sqrt(1*scale)*sin( angle/2);  
    TFor(2,1)       =  sqrt(1*scale)*sin( angle/2);
    TFor(1,3)       =  dispX/2;       
    TFor(2,3)       =  dispY/2;
end
end
%%
function [XLP, YLP] = LogPolarCoordinates(IMAGESIZE, NUMWEDGES,...
    NUMRINGS, RMIN, RMAX, MAXANGLE)
% LOGPOLARCOORDINATES Constructs polar coordinate matrix values which map a
%   variable of interest from Cartesian space to polar space.
h       = IMAGESIZE(1);                                                     % Image Height
w       = IMAGESIZE(2);                                                     % Image Width
nw      = NUMWEDGES;                                                        % Number of Wedges
nr      = NUMRINGS;                                                         % Number of Rings
rMax    = RMAX;                                                             % Maximum Radius
rMin    = RMIN;                                                             % Minimum Radius
xZero   = (w + 1)/2;                                                        % X offset
yZero   = (h + 1)/2;                                                        % Y offset
logR    = linspace(log(rMin), log(rMax), nr);
rv      = exp(logR);
thMax   = MAXANGLE * (1 - 1 / nw);
thv     = linspace(0, thMax, nw);
[r, th] = meshgrid(rv, thv);                                                % Build RHO-Theta Grids
[x, y]  = pol2cart(th, r);                                                  % Convert to Cartesian
XLP     = x + xZero;                                                        % Apply X offset
YLP     = y + yZero;                                                        % Aplly Y offset
end

function imgtform = tformImage(x,y,M,S,imgint)
% TFORMIMAGE Maps images from reference coordinates to current coordinates
%   after image deformation(scaling), shifting, shearing, or rotation
% Inputs:
%   x is the reference N x M coordinates in the x-direction
%   y is the reference N x M coordinates in the y-direction
%   M is the 3 x 3 matrix of global mapping values
%   S is the size of the current image
%   imgint is the intial image
% OUTPUTS:
%   imgtform is the mapped image to the current coordinates

% 2 x nPoints vector of coordinates.
interpPoints = M \ [x(:)'; y(:)'; ones(size(y(:)))'];
% Generate mapped image from raw image
imgtform = imgint(reshape(interpPoints(1,:),S)',...
    reshape(interpPoints(2,:),S)')';
end

function WINDOW = gaussianWindowFilter(DIMENSIONS, WINDOWSIZE, WINDOWTYPE)
% gaussianWindowFilter(DIMENSIONS, WINDOWSIZE, WINDOWTYPE) creates a 2-D
% gaussian window
%
% INPUTS
%   DIMENSIONS = 2 x 1 Vector specifying  the Dimensions (in rows and columns) of the gaussian window filter
%   WINDOWSIZE = 2 x 1 vector specifying the effective window resolution of
%   the gaussian window. WINDOWSIZE can either specify the resolution in
%   pixels or as a fraction of the filter dimensions. This option is
%   controlled by the input WINDOWTYPE.
%   WINDOWTYPE = String specifying whether WINDOWSIZE specifies a
%   resolution in pixels ('pixels') or as a fraction of the window
%   dimensions ('fraction').
%
% OUTPUTS
%   WINDOW = 2-D gaussian window
%
% SEE ALSO
%   findwidth

% Default to an absolute size window type
if nargin < 3
    WINDOWTYPE = 'fraction';
end

if length(DIMENSIONS) == 1
    dims = DIMENSIONS * [1, 1];
else
    dims = DIMENSIONS;
end
% Signal height and width
height  = dims(1);
width   = dims(2);
if length(WINDOWSIZE) == 1
    win_size = WINDOWSIZE * [1, 1];
else
    win_size = WINDOWSIZE;
end
% Determine whether window size is an absolute size or a fraction of the
% window dimensions
if strcmp(WINDOWTYPE, 'fraction')
    windowSizeX = width .* win_size(2);
    windowSizeY = height .* win_size(1);
elseif strcmp(WINDOWTYPE, 'pixels')
    windowSizeX = win_size(2);
    windowSizeY = win_size(1);
else
    error('Invalid window type "%s"\n', WINDOWTYPE);
end
% Standard deviations
[sy, sx] = findGaussianWidth(height, width, windowSizeY, windowSizeX);
% Calculate center of signal
xc = (width-1)/2;
yc = (height-1)/2;
% Create grid of x,y positions to hold gaussian filter data
[xo,yo] = meshgrid(0:(width-1), 0:(height-1));
% Shift the coordinates to make them
% symmetric about the centroid of the array
x = xo - xc; y = yo - yc;
% Calculate gaussian distribution (X)
WindowX = exp( - (x.^2 / (2 * sx^2)));
% Calculate gaussian distribution (Y)
WindowY = exp( - (y.^2 / (2 * sy^2)));
% 2-D Gaussian Distribution
WINDOW = WindowX .* WindowY;
end

function [STDY, STDX] = findGaussianWidth(IMAGESIZEY, IMAGESIZEX, WINDOWSIZEY, WINDOWSIZEX)
% FINDGAUSSIANWIDTH determines the standard deviation of a normalized Gaussian function whose
% area is approximately equal to that of a top-hat function of the desired
% effective window resolution.
%
% John says that the volume under a this Gaussian window will not be
% exactly the volume under the square window. Check into this.
%
% INPUTS
%      xregion = Width of each interrogation region (pixels)
%      yregion = Height of each interrogation region (pixels)
%      xwin = Effective window resolution in the x-direction (pixels)
%      ywin = Effective window resolution in the y-direction (pixels)
%
% OUTPUTS
%       sx = standard deviation of a normalized Gaussian for the x-dimension of the window (pixels)
%       sy = standard deviation of a normalized Gaussian for the y-dimension of the window (pixels)
%
% EXAMPLE
%       xregion = 32;
%       yregion = 32;
%       xwin = 16;
%       ywin = 16;
%       [sx sy] = findGaussianWidth(xregion, yregion, xwin, ywin);
%
% SEE ALSO
%

% Initial guess for standard deviaitons are half the respective window sizes
STDX = 50 * WINDOWSIZEX;
STDY = 50 * WINDOWSIZEY;
% Generate x and y domains
x = - IMAGESIZEX/2 : IMAGESIZEX/2;
y = - IMAGESIZEY/2 : IMAGESIZEY/2;
% Generate normalized zero-mean Gaussian windows
xgauss = exp(-(x).^2/(2 * STDX^2));
ygauss = exp(-(y).^2/(2 * STDY^2));
% Calculate areas under gaussian curves
xarea = trapz(x, xgauss);
yarea = trapz(y, ygauss);
if WINDOWSIZEX < xarea
    % Calculate initial errors of Gaussian windows with respect to desired
    % effective window resolution
    xerr = abs(1 - xarea / WINDOWSIZEX);
    % Initialize max and min values of standard deviation for Gaussian x-window
    sxmax = 100 * IMAGESIZEX;
    sxmin = 0;
    % Iteratively determine the standard deviation that gives the desired
    % effective Gaussian x-window resolution
    % Loop while the error of area under curve is above the specified error tolerance
    while xerr > 1E-5
        %  If the area under the Gaussian curve is less than that of the top-hat window
        if xarea < WINDOWSIZEX
            % Increase the lower bound on the standard deviation
            sxmin = sxmin + (sxmax - sxmin) / 2;
        else
            % Otherwise, increase the upper bound on the standard deviation
            sxmax =  sxmin + (sxmax - sxmin) / 2;
        end
        % Set the standard deviation to halfway between its lower and upper bounds
        STDX = sxmin + (sxmax - sxmin) / 2;
        % Generate a Gaussian curve with the specified standard deviation
        xgauss = exp(-(x).^2/(2 * STDX^2));
        % Calculate the area under this Gaussian curve via numerical
        % integration using the Trapezoidal rule
        xarea = trapz(x,xgauss);
        % Calculate the error of the area under the Gaussian curve with
        % respect to the desired area
        xerr = abs(1 - xarea / WINDOWSIZEX);
    end
end
if WINDOWSIZEY < yarea
    yerr = abs(1 - yarea / WINDOWSIZEY);
    % Initialize max and min values of standard deviation for Gaussian y-window
    symax = 100 * IMAGESIZEY;
    symin = 0;
    % Iteratively determine the standard deviation that gives the desired
    % effective Gaussian y-window resolution
    % Loop while the error of area under curve is above the specified error tolerance
    while yerr > 1E-5
        % If the area under the Gaussian curve is less than that of the top-hat window
        if yarea < WINDOWSIZEY
            % Increase the lower bound on the standard deviation
            symin = symin + (symax - symin) / 2;
        else
            % Otherwise, increase the upper bound on the standard deviation
            symax =  symin + (symax - symin) / 2;
        end
        % Set the standard deviation to halfway between its lower and upper bounds
        STDY = symin + (symax - symin) / 2;
        % Generate a Gaussian curve with the specified standard deviation
        ygauss = exp(-(y).^2/(2 * STDY^2));
        % Calculate the area under this Gaussian curve via
        % numerical integration using the Trapezoidal rule
        yarea = trapz(y, ygauss);
        % Calculate the error of the area under the Gaussian curve with
        % respect to the desired area
        yerr = abs(1 - yarea / WINDOWSIZEY);
    end
end
end

function [u,v,M,D,DX, DY, PEAK_ANGLE, PEAK_ECCENTRICITY] = subpixel(...
    SPATIAL_CORRELATION_PLANE,...
    CORRELATION_WIDTH, CORRELATION_HEIGHT, WEIGHTING_MATRIX, ...
    PEAK_FIT_METHOD, FIND_MULTIPLE_PEAKS, PARTICLE_DIAMETER_2D)
%
%     Copyright (C) 2012  Virginia Polytechnic Institute and State
%     University
%
%     Copyright 2014.  Los Alamos National Security, LLC. This material was
%     produced under U.S. Government contract DE-AC52-06NA25396 for Los
%     Alamos National Laboratory (LANL), which is operated by Los Alamos
%     National Security, LLC for the U.S. Department of Energy. The U.S.
%     Government has rights to use, reproduce, and distribute this software.
%     NEITHER THE GOVERNMENT NOR LOS ALAMOS NATIONAL SECURITY, LLC MAKES ANY
%     WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY FOR THE USE OF
%     THIS SOFTWARE.  If software is modified to produce derivative works,
%     such modified software should be clearly marked, so as not to confuse
%     it with the version available from LANL.
%
%     prana is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
%
%     This program is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
%
%     You should have received a copy of the GNU General Public License
%     along with this program.  If not, see <http://www.gnu.org/licenses/>.

%intialize indices
cc_x = -floor(CORRELATION_WIDTH/2):ceil(CORRELATION_WIDTH/2)-1;
cc_y = -floor(CORRELATION_HEIGHT/2):ceil(CORRELATION_HEIGHT/2)-1;
% Set values for peak eccentricity and angle
% so that the function returns them properly
% even if the Guassian least-squares fit method isn't used.
PEAK_ECCENTRICITY = 0;
%find maximum correlation value
[M,I] = max(SPATIAL_CORRELATION_PLANE(:));
% Use 4 standard deviations for the peak sizing (e^-2)
sigma = 4;
%if correlation empty
if M==0
    if FIND_MULTIPLE_PEAKS
        u=zeros(1,3);
        v=zeros(1,3);
        M=zeros(1,3);
        D=zeros(1,3);
        DX=zeros(1,3);
        DY=zeros(1,3);
        PEAK_ANGLE = zeros(1,3);
    else
        u=0; v=0; M=0; D=0; DX=0; DY=0; PEAK_ANGLE=0;
    end
else
    if FIND_MULTIPLE_PEAKS
        u=zeros(1,3);
        v=zeros(1,3);
        D=zeros(1,3);
        DX=zeros(1,3);
        DY=zeros(1,3);
        PEAK_ANGLE=zeros(1,3);
        %Locate peaks using imregionalmax
        A=imregionalmax(SPATIAL_CORRELATION_PLANE);
        peakmat=SPATIAL_CORRELATION_PLANE.*A;
        for i=2:3
            peakmat(peakmat==M(i-1))=0;
            [M(i),I(i)]=max(peakmat(:));
        end
        j=length(M);
    else
        u=zeros(1,1);
        v=zeros(1,1);
        D=zeros(1,1);
        DX=0; DY=0; PEAK_ANGLE=0;
        j=1;
    end
    for i=1:j
        method=PEAK_FIT_METHOD;
        %find x and y indices
        shift_locy = 1+mod(I(i)-1,CORRELATION_HEIGHT);
        shift_locx = ceil(I(i)/CORRELATION_HEIGHT);
        shift_errx=[];
        shift_erry=[];
        %find subpixel displacement in x
        if CORRELATION_WIDTH == 1
            shift_errx = 1; method=1;
        elseif shift_locx == 1
            %boundary condition 1
            shift_errx =  SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx+1 )/M(i); method=1;
        elseif shift_locx == CORRELATION_WIDTH
            %boundary condition 2
            shift_errx = -SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx-1 )/M(i); method=1;
        elseif SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx+1 ) == 0
            %endpoint discontinuity 1
            shift_errx = -SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx-1 )/M(i); method=1;
        elseif SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx-1 ) == 0
            %endpoint discontinuity 2
            shift_errx =  SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx+1 )/M(i); method=1;
        end
        if CORRELATION_HEIGHT == 1
            shift_erry = 1; method=1;
        elseif shift_locy == 1
            %boundary condition 1
            shift_erry = -SPATIAL_CORRELATION_PLANE( shift_locy+1 , shift_locx )/M(i); method=1;
        elseif shift_locy == CORRELATION_HEIGHT
            %boundary condition 2
            shift_erry =  SPATIAL_CORRELATION_PLANE( shift_locy-1 , shift_locx )/M(i); method=1;
        elseif SPATIAL_CORRELATION_PLANE( shift_locy+1 , shift_locx ) == 0
            %endpoint discontinuity 1
            shift_erry =  SPATIAL_CORRELATION_PLANE( shift_locy-1 , shift_locx )/M(i); method=1;
        elseif SPATIAL_CORRELATION_PLANE( shift_locy-1 , shift_locx ) == 0
            %endpoint discontinuity 2
            shift_erry = -SPATIAL_CORRELATION_PLANE( shift_locy+1 , shift_locx )/M(i); method=1;
        end
        if method==2
            %%%%%%%%%%%%%%%%%%%%
            % 4-Point Gaussian %
            %%%%%%%%%%%%%%%%%%%%
            %Since the case where M is located at a border will default to
            %the 3-point gaussian and we don't have to deal with
            %saturation, just use 4 points in a tetris block formation:
            %
            %             *
            %            ***
            points=[shift_locy   shift_locx   SPATIAL_CORRELATION_PLANE(shift_locy  ,shift_locx  );...
                shift_locy-1 shift_locx   SPATIAL_CORRELATION_PLANE(shift_locy-1,shift_locx  );...
                shift_locy   shift_locx-1 SPATIAL_CORRELATION_PLANE(shift_locy  ,shift_locx-1);...
                shift_locy   shift_locx+1 SPATIAL_CORRELATION_PLANE(shift_locy  ,shift_locx+1)];
            [~,IsortI] = sort(points(:,3),'descend');
            points = points(IsortI,:);
            x1=points(1,2); x2=points(2,2); x3=points(3,2); x4=points(4,2);
            y1=points(1,1); y2=points(2,1); y3=points(3,1); y4=points(4,1);
            a1=points(1,3); a2=points(2,3); a3=points(3,3); a4=points(4,3);
            peak_angle(1) = (x4^2)*(y2 - y3) + (x3^2)*(y4 - y2) + ((x2^2) + (y2 - y3)*(y2 - y4))*(y3 - y4);
            peak_angle(2) = (x4^2)*(y3 - y1) + (x3^2)*(y1 - y4) - ((x1^2) + (y1 - y3)*(y1 - y4))*(y3 - y4);
            peak_angle(3) = (x4^2)*(y1 - y2) + (x2^2)*(y4 - y1) + ((x1^2) + (y1 - y2)*(y1 - y4))*(y2 - y4);
            peak_angle(4) = (x3^2)*(y2 - y1) + (x2^2)*(y1 - y3) - ((x1^2) + (y1 - y2)*(y1 - y3))*(y2 - y3);
            gamma(1) = (-x3^2)*x4 + (x2^2)*(x4 - x3) + x4*((y2^2) - (y3^2)) + x3*((x4^2) - (y2^2) + (y4^2)) + x2*(( x3^2) - (x4^2) + (y3^2) - (y4^2));
            gamma(2) = ( x3^2)*x4 + (x1^2)*(x3 - x4) + x4*((y3^2) - (y1^2)) - x3*((x4^2) - (y1^2) + (y4^2)) + x1*((-x3^2) + (x4^2) - (y3^2) + (y4^2));
            gamma(3) = (-x2^2)*x4 + (x1^2)*(x4 - x2) + x4*((y1^2) - (y2^2)) + x2*((x4^2) - (y1^2) + (y4^2)) + x1*(( x2^2) - (x4^2) + (y2^2) - (y4^2));
            gamma(4) = ( x2^2)*x3 + (x1^2)*(x2 - x3) + x3*((y2^2) - (y1^2)) - x2*((x3^2) - (y1^2) + (y3^2)) + x1*((-x2^2) + (x3^2) - (y2^2) + (y3^2));
            delta(1) = x4*(y2 - y3) + x2*(y3 - y4) + x3*(y4 - y2);
            delta(2) = x4*(y3 - y1) + x3*(y1 - y4) + x1*(y4 - y3);
            delta(3) = x4*(y1 - y2) + x1*(y2 - y4) + x2*(y4 - y1);
            delta(4) = x3*(y2 - y1) + x2*(y1 - y3) + x1*(y3 - y2);
            deno = 2*(log(a1)*delta(1) + log(a2)*delta(2) + log(a3)*delta(3) + log(a4)*delta(4));
            x_centroid = (log(a1)*peak_angle(1) + log(a2)*peak_angle(2) + log(a3)*peak_angle(3) + log(a4)*peak_angle(4))/deno;
            y_centroid = (log(a1)*gamma(1) + log(a2)*gamma(2) + log(a3)*gamma(3) + log(a4)*gamma(4))/deno;
            shift_errx=x_centroid-shift_locx;
            shift_erry=y_centroid-shift_locy;
            betas = abs((log(a2)-log(a1))/((x2-x_centroid)^2+(y2-y_centroid)^2-(x1-x_centroid)^2-(y1-y_centroid)^2));
            D(i)=sqrt(sigma^2/(2*betas));
        elseif any(method==[3 4])
            %%%%%%%%%%%%%%%%%%%%%%%%%%
            % Gaussian Least Squares %
            %%%%%%%%%%%%%%%%%%%%%%%%%%
            %convert the particle diameter to diameter of equivalent correlation peak
            D1 = sqrt(2) .* PARTICLE_DIAMETER_2D(1);
            D2 = sqrt(2) .* PARTICLE_DIAMETER_2D(2);
            goodSize = 0;  %gets set =1 after fit, but reset to 0 if betaX or betaY are bigger than 2*D1 or 2*D2
            %keep trying while method not 1 (G.3pt.fit), and the search diameter (2x expected diam.) is less than half the window size
            while ~goodSize && method~=1
                %Find a suitable window around the peak (+/- D1,D2)
                x_min=shift_locx-ceil(D1); x_max=shift_locx+ceil(D1);
                y_min=shift_locy-ceil(D2); y_max=shift_locy+ceil(D2);
                if x_min<1
                    x_min=1;
                end
                if x_max>CORRELATION_WIDTH
                    x_max=CORRELATION_WIDTH;
                end
                if y_min<1
                    y_min=1;
                end
                if y_max>CORRELATION_HEIGHT
                    y_max=CORRELATION_HEIGHT;
                end
                points = double(SPATIAL_CORRELATION_PLANE(y_min:y_max,x_min:x_max).* ...
                    WEIGHTING_MATRIX(y_min:y_max,x_min:x_max));
                % Subtract the minimum value from the points matrix
                points_min_sub = points - min(points(:));
                % Normalize the points matrix so the max value is one
                points_norm = points_min_sub ./ max(points_min_sub(:));
                %Options for the lsqnonlin solver using Levenberg-Marquardt solver
                options=optimset('MaxIter',1200,'MaxFunEvals',5000,'TolX',1e-6,'TolFun',1e-6,...
                    'Display','off','DiffMinChange',1e-7,'DiffMaxChange',1,...
                    'Algorithm','levenberg-marquardt');
                % Set empty lower bounds (LB) and upper bounds (UB)
                % for the least squares solver LSQNONLIN.
                LB = [];
                UB = [];
                x0 = [1, ...
                    0.5*(sigma/D1)^2, ...
                    0.5*(sigma/D2)^2, ...
                    shift_locx, ...
                    shift_locy, ...
                    0];
                [xloc, yloc]=meshgrid(x_min:x_max,y_min:y_max);
                %Run solver; default to 3-point gauss if it fails
                try
                    [xvars]=lsqnonlin(@leastsquares2D,x0, LB, UB,options,points_norm(:),[yloc(:),xloc(:)], method);
                    shift_errx=xvars(4)-shift_locx;
                    shift_erry=xvars(5)-shift_locy;
                    %convert beta to diameter, diameter = 4*std.dev.
                    dA = sigma/sqrt(2*abs(xvars(2)));    %diameter of axis 1
                    dB = sigma/sqrt(2*abs(xvars(3)));    %diameter of axis 2
                    % Find the equivalent diameter for a circle with
                    % equal area and return that value
                    D(i) = sqrt(dA*dB);
                    peak_angle = mod(xvars(6),2*pi);
                    % Calculate the lengths of the major and minor axes
                    % of the best-fit elliptical Gaussian
                    major_axis_length = max(dA, dB);
                    minor_axis_length = min(dA, dB);
                    % Calculate the eccentricity of the
                    % elliptical Gaussian peak.
                    PEAK_ECCENTRICITY = sqrt(1 - ...
                        minor_axis_length^2 / major_axis_length^2);
                    % These are the lengths of the projections of the
                    % elliptical Gaussian peak onto the horizontal and vertical
                    % axes.
                    dX = max( abs(dA*cos(peak_angle)), abs(dB*sin(peak_angle)) );
                    dY = max( abs(dA*sin(peak_angle)), abs(dB*cos(peak_angle)) );
                    DX(i) = dX;
                    DY(i) = dY;
                    PEAK_ANGLE(i) = peak_angle;
                    %LSqF didn't fail...
                    goodSize = 1;
                    %if D1 or D2 are already too big, just quit - it's
                    %the best we're going to do.
                    %Have to check in loop, if check at while statement,
                    %might never size it at all.
                    if 2*D1<CORRELATION_WIDTH/2 && 2*D2<CORRELATION_HEIGHT/2
                        goodSize = 1;
                    end
                catch err
                    %warning(err.message)
                    disp(err.message)
                    method=1;
                end
            end %while trying to fit region
        end %if method==2,3,4
        if method==1
            %%%%%%%%%%%%%%%%%%%%
            % 3-Point Gaussian %
            %%%%%%%%%%%%%%%%%%%%
            if isempty(shift_errx)
                % Gaussian fit
                lCm1 = log(SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx-1 )*WEIGHTING_MATRIX( shift_locy , shift_locx-1 ));
                lC00 = log(SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx   )*WEIGHTING_MATRIX( shift_locy , shift_locx   ));
                lCp1 = log(SPATIAL_CORRELATION_PLANE( shift_locy , shift_locx+1 )*WEIGHTING_MATRIX( shift_locy , shift_locx+1 ));
                if (2*(lCm1+lCp1-2*lC00)) == 0
                    shift_errx = 0;
                    dX = nan;
                else
                    shift_errx = (lCm1-lCp1)/(2*(lCm1+lCp1-2*lC00));
                    betax = abs(lCm1-lC00)/((-1-shift_errx)^2-(shift_errx)^2);
                    dX = sigma./sqrt((2*betax));
                end
            else
                dX = nan;
            end
            if isempty(shift_erry)
                lCm1 = log(SPATIAL_CORRELATION_PLANE( shift_locy-1 , shift_locx )*WEIGHTING_MATRIX( shift_locy-1 , shift_locx ));
                lC00 = log(SPATIAL_CORRELATION_PLANE( shift_locy   , shift_locx )*WEIGHTING_MATRIX( shift_locy   , shift_locx ));
                lCp1 = log(SPATIAL_CORRELATION_PLANE( shift_locy+1 , shift_locx )*WEIGHTING_MATRIX( shift_locy+1 , shift_locx ));
                if (2*(lCm1+lCp1-2*lC00)) == 0
                    shift_erry = 0;
                    dY = nan;
                else
                    shift_erry = (lCm1-lCp1)/(2*(lCm1+lCp1-2*lC00));
                    betay = abs(lCm1-lC00)/((-1-shift_erry)^2-(shift_erry)^2);
                    dY = sigma./sqrt((2*betay));
                end
            else
                dY = nan;
            end
            D(i) = nanmean([dX dY]);
            DX(i) = dX;
            DY(i) = dY;
        end
        u(i)=cc_x(shift_locx)+shift_errx;
        v(i)=cc_y(shift_locy)+shift_erry;
        if isinf(u(i)) || isinf(v(i))
            u(i)=0; v(i)=0;
        end
    end
end
end

function F = leastsquares2D(x,mapint_i,locxy_i,method)
% function F = leastsquares2D(x,mapint_i,locxy_i,method)
% This function is called by lsqnonlin if the least squares or continuous
% least squares method has been chosen. It solve (leastsqures) for a
% Gaussian surface that best fist a list of sample points.  The code has
% been updated to now handle eliptical Gaussian shapes using a
% trigonometric formulation for an arbitrary eliptical Gaussian function
% taken from ( Scharnowski (2012) Exp Fluids).
%
% Inputs:
%  x:        Is a vectore containing an intial guess at the parameter values
%            for the gaussian fit.  [Max Value, Beta in the X direction,
%            Beta in the Y direction, Estimated Centroid for X, Estimated
%            Centroid for Y, Estimated Orientation Angle]
%  mapint_i: List of intensity values.
%  locxy_i:  Location of intensity samples for X and Y
%  method:   This switches between Standard Gaussian (3) and Continous
%            Gaussian (4).
%
% Outputs:
% F:         Is the variable being minimized - the difference between the
%            gaussian curve and the actual intensity values.
%
% Adapted from M. Brady's 'leastsquaresgaussfit' and 'mapintensity'
% Edited:
% B.Drew - 7.18.2008
% S. Raben - 7.24.2012
I0=x(1);
betasx=x(2);
betasy=x(3);
x_centroid=x(4);
y_centroid=x(5);
alpha = x(6);
if method==3
    xp = locxy_i(:,2);
    yp = locxy_i(:,1);
    % map an intensity profile of a gaussian function
    gauss_int = I0   * exp(-abs(betasx).*(cos(alpha).*(xp-x_centroid) - ...
        sin(alpha)  .* (yp-y_centroid)).^2 - ...
        abs(betasy) .* (sin(alpha).*(xp-x_centroid) + ...
        cos(alpha)  .* (yp-y_centroid)).^2);
elseif method==4
    %Just like in the continuous four-point method, lsqnonlin tries negative
    %values for x(2) and x(3), which will return errors unless the abs() function is
    %used in front of all the x(2)'s.
    num1=(I0*pi)/4;
    num2=sqrt(abs(mean([betasx betasy])));
    S = size(mapint_i);
    gauss_int = zeros(S(1),S(2));
    xp = zeros(size(mapint_i));
    yp = zeros(size(mapint_i));
    for ii = 1:length(mapint_i)
        xp(ii) = locxy_i(ii,1)-0.5;
        yp(ii) = locxy_i(ii,2)-0.5;
        erfx1 = erf(num2*(xp(ii)-x_centroid));
        erfy1 = erf(num2*(yp(ii)-y_centroid));
        erfx2 = erf(num2*(xp(ii)+1-x_centroid));
        erfy2 = erf(num2*(yp(ii)+1-y_centroid));
        % map an intensity profile of a gaussian function:
        gauss_int(ii)=(num1/abs(betas))*(erfx1*(erfy1-erfy2)+erfx2*(-erfy1+erfy2));
    end
end
% compare the Gaussian curve to the actual pixel intensities
F = mapint_i-gauss_int;
end

function [N]=socdiff(N,dx,dir)
% Sam found error 2008/05/14, k loop should be commented
size_N = size(N);
if isempty(dir)
    if size_N(1)~=1
        dir = 1;
    elseif size_N(2)~=1
        dir = 2;
    elseif size_N(3)~=1
        dir = 3;
    else
        dir = 1;
    end
end
ndim_N = ndims(N);
if ndim_N > 3
    error('function only defined up to 3D matrices')
end
if isempty(dx)
    dx = 1;
end
N = permute(N, [dir, 1:dir-1, dir+1:ndim_N]);
size_N = size(N);   %find again for permuted matrix
ndim_N = ndims(N);
NI = size_N(1);
NJ = size_N(2);
if ndim_N == 3
    NK = size_N(3);
else
    NK = 1;
end
if NI < 3
    error('stencil size is 3 pts in active direction')
end
DN = zeros(NI,NJ,NK);
DN(1     ,:,:) = ( -N( 3   ,:,:) +4*N(  2 ,:,:) -3*N(1     ,:,:)) / (2*dx);
DN(2:NI-1,:,:) = (  N( 3:NI,:,:)                -  N(1:NI-2,:,:)) / (2*dx);
DN(NI    ,:,:) = (3*N(NI   ,:,:) -4*N(NI-1,:,:) +  N(  NI-2,:,:)) / (2*dx);
N = ipermute(DN, [dir, 1:dir-1, dir+1:ndim_N]);
end

function [W] = energyfilt(Nx,Ny,d,q)
% --- RPC Spectral Filter Subfunction ---
if numel(d) == 1
    d(2) = d;
end
%assume no aliasing
if nargin<4
    q = 0;
end
%initialize indices
[k1,k2]=meshgrid(-pi:2*pi/Ny:pi-2*pi/Ny,-pi:2*pi/Nx:pi-2*pi/Nx);
%particle-image spectrum
Ep = (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*k1.^2/16).*exp(-d(1)^2*k2.^2/16);
%aliased particle-image spectrum
Ea = (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1+2*pi).^2/16).*exp(-d(1)^2*(k2+2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1-2*pi).^2/16).*exp(-d(1)^2*(k2+2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1+2*pi).^2/16).*exp(-d(1)^2*(k2-2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1-2*pi).^2/16).*exp(-d(1)^2*(k2-2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1+0*pi).^2/16).*exp(-d(1)^2*(k2+2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1+0*pi).^2/16).*exp(-d(1)^2*(k2-2*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1+2*pi).^2/16).*exp(-d(1)^2*(k2+0*pi).^2/16)+...
    (pi*255*(d(1)*d(2))/8)^2*exp(-d(2)^2*(k1-2*pi).^2/16).*exp(-d(1)^2*(k2+0*pi).^2/16);
%noise spectrum
En = pi/4*Nx*Ny;
%DPIV SNR spectral filter
W  = Ep./((1-q)*En+(q)*Ea);
W  = W'/max(max(W));
end

%     if mod(size(FFT01,2),2) == 0
%         mFT01 = imtranslate(SptWindow.*abs(FFT01),[-0.5 -0.5]);
%     else
%         mFT01 = imtranslate(SptWindow.*abs(FFT01),[0 -0.5]);
%     end
%     if mod(size(FFT02,2),2) == 0
%         mFT02 = imtranslate(SptWindow.*abs(FFT02),[-0.5 -0.5]);
%     else
%         mFT02 = imtranslate(SptWindow.*abs(FFT02),[0 -0.5]);
%     end
%     % Run Fourier-Mellin Transform on FFTs
%     FMT01   = interp2(fftshift(mFT01),xLP,yLP,'spline',0);
%     FMT02   = interp2(fftshift(mFT02),xLP,yLP,'spline',0);
%       % Calculate FFTs of FMTs
%     FMC01   = fft2(FMCWindow.*FMT01);
%     FMC02   = fft2(FMCWindow.*FMT02);

%     if mod(size(FFT01,2),2) == 0
%         mFT01 = imtranslate(1.*abs(FFT01),[-0.5 -0.5]);
%         mFT02 = imtranslate(1.*abs(FFT02),[-0.5 -0.5]);
%     else
%         mFT01 = imtranslate(1.*abs(FFT01),[0 -0.5]);
%         mFT02 = imtranslate(1.*abs(FFT02),[0 -0.5]);
%     end
%     FMC01           = fft2(FMCWindow.*interp2(mFT01,xLP,yLP,'spline',0));
%     FMC02           = fft2(FMCWindow.*interp2(mFT02,xLP,yLP,'spline',0));

% dilateMaxRad    = dMaxOri*scaleFactor;
% dispSInst       = dispSOri*scaleFactor;
% winsize         = wSizeOri*scaleFactor;
% tVect           = tVect-tVect(1);
% tspan           = min(tVect(:)):1/deltaTime:max(tVect(:));                      % Generate linearly spaced time series
% if numel(tVect) < numel(dispSInst)
%     dispSInst = dispSInst(1:numel(tVect));
% end
% tstamp = isoutlier(dispSInst(:),'movmedian',9,'ThresholdFactor',3);% | isoutlier(dispSInst(:),'quartiles','ThresholdFactor',6);
% for n = 1:numel(tstamp)
%     if tstamp(n) == 1
%         tvals = abs(tVect(n) - tVect);
%         inds = 1:numel(tVect);
%         [~,sind] = sort(tvals,'ascend');
%         inds = inds(sind);
%         dispSInst(n) = median(dispSInst(inds(2:9)));
%     end
% end
% tstamp = isoutlier(dispSInst(:),'movmedian',9,'ThresholdFactor',2);% | isoutlier(dispSInst(:),'quartiles','ThresholdFactor',6);
% for n = 1:numel(tstamp)
%     if tstamp(n) == 1
%         tvals = abs(tVect(n) - tVect);
%         inds = 1:numel(tVect);
%         [~,sind] = sort(tvals,'ascend');
%         inds = inds(sind);
%         dispSInst(n) = median(dispSInst(inds(2:9)));
%     end
% end
% dilateVel   = interp1(tVect,dispSInst(:),tspan,'pchip');                                % Interpolate to fill in missing values during flash
% dilation    = (dilateMaxRad/dilateMinRad).^...
%     (-cumsum(dilateVel(:),1)/(winsize/2));                                  % Compute dilation through dilation rate integration
% % Set initial fit paramaters for rheological model (Fan & Yao, 2010)
% %   Kc  - Iris constrictor elastic constant
% %   Kd  - Iris dilator elastic constant
% %   nu  - Iris viscosity constant
% Kc = 0.0536; Kd = 1.0829; nu = 3.2583;
% dilatVelCur     = -dilateVel(:);                                            % Initialize current dilation rate series for nLSQ model fitting
% dilatVelPrev    = zeros(size(dilatVelCur));                                 % Initialize previous dilation rate series for nLSQ model fitting
% iterations      = 1;                                                        % Initialize iteration number for while loop processing
% % Run iterative rheological model fitting on dilation and dilation rate
% % time series data. During the while loop iteration 
% %   (1) current dilation rate data is smoothed using a Fourier low pass filter 
% %   (2) current dilation after smoothing is calculated
% %   (3) approximations for dilation acceleration and the stimulus forcing
% %       function are obtained
% %   (4) nLSQ fitting is performed on the raw, interpolated dilation rate
% %       and dilation with a smooth forcing function
% %   (5) Fit parameters are updated from the nLSQ
% %   (6) current dilation rate data is updated from the nLSQ output
% % Loop stops once the RMS for dilation rate has minimized OR the number of
% % iterations passes 5 (need a stopping criteria so loop doesn't over-smooth
% %%
% while rms(abs(dilatVelCur(:)-dilatVelPrev(:)),1) > 1E-2 && iterations <= 1
%     %%
%     dilatVelPrev    = dilatVelCur;                                          % Update previous dilation rate series
%     dilatVelCur     = smoothdata(dilatVelCur,'movmean',3);
%     dilationCur     = (dilateMaxRad/dilateMinRad).^...
%         (cumsum(dilatVelCur(:),1)/(winsize/2));                             % Compute instantaneous dilation
%     dilatAccCur     = socdiff(dilatVelCur,1/deltaTime,1);                   % Approximate the dilation acceleration
%     forceFunc       = dilatAccCur(:) + Kc*(0.25-dilationCur).^2 -...
%         Kd*(1.00-dilationCur).^2 + nu*dilatVelCur(:);                       % Approximate the stimulus forcing function from the rheological model
%     forceFunc       = forceFunc - forceFunc(1);                             % Correct for bias at first index
%     soln = [dilation(:), -dilateVel(:)];                                    % Initialize ydata for nLSQ using raw dilation and dilation rate 
%     xt0  = [1, 0, Kc, Kd, nu];                                              % Initialize fitting parameters xdata
%     options = optimoptions('lsqcurvefit','Algorithm',...
%         'trust-region-reflective','Display','off',...
%         'MaxIterations',50,'MaxFunctionEvaluations',50);                    % Set nLSQ options (tweaking might speed things up)
%     lb = [1.00 0.00 1E-3*Kc 1E-3*Kd 1E-3*nu];                               % Set lower bound (ensures dilation and dilation rate first index are constant)
%     ub = [1.00 0.00 1E+3*Kc 1E+3*Kd 1E+3*nu];                                % Set upper bound (ensures dilation and dilation rate first index are constant)
%     %%
%     [ pbest, ~, presidual, ~, ~] = lsqcurvefit(@(t,x)...
%         PLRModel(t,x,forceFunc),xt0,tspan(:),soln,lb,ub,options);           % Perform nLSQ data fitting for rheological model onto raw data
%     dilatVelCur = -dilateVel(:)+presidual(:,2);                             % Update current dilation rate from model fit
%     Kc  = pbest(3); Kd  = pbest(4); nu = pbest(5);                          % Update fitting parameters
%     iterations  = iterations + 1;                                           % Update iteration number
% end
% dilationInst    = dilation(:) + presidual(:,1);                             % Update dilation from model fit
% dilateVelInst   = dilateVel(:)- presidual(:,2);  