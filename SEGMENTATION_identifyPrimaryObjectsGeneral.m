function ObjectsLabeled = SEGMENTATION_identifyPrimaryObjectsGeneral(OriginalImage, varargin)
    defaultMinDiameter = 25;
    defaultImageResizeFactor = 0.25;
    defaultMaximaSuppressionSize = 10;
    defaultSolidityThreshold = 0.95;
    defaultAreaThreshold = 100;
    defaultMinimumThreshold = 250;
    
    p = inputParser;
    p.addRequired('OriginalImage', @isnumeric);
    addOptional(p,'SecondaryImage', @isnumeric);
    addOptional(p,'LocalMaximaType', 'Shape', @ischar);
    addOptional(p,'WatershedTransformImageType', 'Distance', @ischar)
    addOptional(p,'MinDiameter', defaultMinDiameter, @isnumeric)
    addOptional(p,'ImageResizeFactor', defaultImageResizeFactor, @isnumeric)
    addOptional(p,'MaximaSuppressionSize', defaultMaximaSuppressionSize, @isnumeric)
    addOptional(p,'SolidityThreshold', defaultSolidityThreshold, @isnumeric)
    addOptional(p,'AreaThreshold', defaultAreaThreshold, @isnumeric)
    addOptional(p,'MinimumThreshold', defaultMinimumThreshold, @isnumeric)
    p.parse(OriginalImage, varargin{:});
    
    MinDiameter = p.Results.MinDiameter;
    ImageResizeFactor = p.Results.ImageResizeFactor;
    MaximaSuppressionSize = p.Results.MaximaSuppressionSize; 
    MinimumThreshold = p.Results.MinimumThreshold;
    
    OriginalImage_normalized = imnormalize(double(OriginalImage));
    SizeOfSmoothingFilter=MinDiameter;
    BlurredImage = imfilter(OriginalImage_normalized, fspecial('gaussian', round(SizeOfSmoothingFilter), round(SizeOfSmoothingFilter/3.5)));
    
    % THRESHOLDING
    ThresholdedImage = imfill(BlurredImage > MinimumThreshold, 'holes');
    edgeImage = imfill(edge(BlurredImage, 'canny'), 'holes');
    Objects = imfill(edgeImage + im2bw(BlurredImage, graythresh(BlurredImage)), 'holes') & ThresholdedImage;
    Objects = imopen(Objects, strel('disk',2));
    Objects = imclearborder(Objects);
    
    % FIRST-TIER OBJECT: Keep round objects as they are to avoid
    % over-segmenting
    ObjectsLabeled = bwlabel(Objects);
    props = regionprops(ObjectsLabeled, 'Solidity');
    primarySegmentation = ismember(ObjectsLabeled, find([props.Solidity] >= p.Results.SolidityThreshold));

    % Optional for certain cell lines: filter out objects that look like
    % beans and keep them as they are to avoid over-segmentation.
    
    %     ObjectsLabeled = bwlabel(Objects);
    %     beanshapes = zeros(1, length(props));
    %     props = regionprops(ObjectsLabeled, 'FilledImage');
    %     for k=1:length(props)
    %         convexHull = bwconvhull(props(k).FilledImage) & ~props(k).FilledImage;
    %         convexHull = imopen(convexHull, strel('square', 3));
    %         components = bwconncomp(convexHull);
    %         beanshapes(k) = components.NumObjects;
    %     end
    %     primarySegmentation = primarySegmentation | ismember(ObjectsLabeled, find(beanshapes < 2));

    % REFINE PARAMETERS: Use information about primary segmentation to inform selection of
    % smoothing filter and maxima suppression size for watershed
    % segmentation.
    if(sum(primarySegmentation(:)) > 0)
        props = bwconncomp(primarySegmentation);
        SizeOfSmoothingFilter = round(2 * sqrt(median(cellfun(@length, props.PixelIdxList))) / pi);
        MaximaSuppressionSize = round(0.2 * SizeOfSmoothingFilter);
    end
    
    MaximaMask = getnhood(strel('disk', MaximaSuppressionSize));
    
    Objects = Objects & ~primarySegmentation;
    BlurredImage(~Objects) = 0;
    
    if(sum(logical(Objects(:))) > 0)
        % IDENTIFY LOCAL MAXIMA IN THE INTENSITY OF DISTANCE TRANSFORMED IMAGE
        if strcmp(p.Results.LocalMaximaType, 'Intensity')
            BlurredImage = imfilter(OriginalImage_normalized, fspecial('gaussian', round(SizeOfSmoothingFilter), round(SizeOfSmoothingFilter/3.5)));
            BlurredImage(~Objects) = 0;
            
            ResizedBlurredImage = imresize(BlurredImage,ImageResizeFactor,'bilinear');
            MaximaImage = ResizedBlurredImage;
            MaximaImage(ResizedBlurredImage < ordfilt2(ResizedBlurredImage,sum(MaximaMask(:)),MaximaMask)) = 0;
            MaximaImage = imresize(MaximaImage,size(BlurredImage),'bilinear');
            MaximaImage(~Objects) = 0;
            MaximaImage = bwmorph(MaximaImage,'shrink',inf);
        else
            DistanceTransformedImage = bwdist(~Objects, 'euclidean');
            DistanceTransformedImage = DistanceTransformedImage + 0.001*rand(size(DistanceTransformedImage));
            ResizedDistanceTransformedImage = imresize(DistanceTransformedImage,ImageResizeFactor,'bilinear');
            MaximaImage = ones(size(ResizedDistanceTransformedImage));
            MaximaImage(ResizedDistanceTransformedImage < ordfilt2(ResizedDistanceTransformedImage,sum(MaximaMask(:)),MaximaMask)) = 0;
            MaximaImage = imresize(MaximaImage,size(Objects),'bilinear');
            MaximaImage(~Objects) = 0;
            MaximaImage = bwmorph(MaximaImage,'shrink',inf);
        end
        
        %GENERATE WATERSHEDS TO SEPARATE TOUCHING NUCLEI
        if strcmp(p.Results.WatershedTransformImageType,'Intensity')
            %%% Overlays the objects markers (maxima) on the inverted original image so
            %%% there are black dots on top of each dark object on a white background.
            Overlaid = imimposemin(-BlurredImage,MaximaImage);
        else
            if ~exist('DistanceTransformedImage','var')
                DistanceTransformedImage = bwdist(~Objects);
            end
            Overlaid = imimposemin(-DistanceTransformedImage,MaximaImage);
        end
        
        WatershedBoundaries = watershed(Overlaid) > 0;
        Objects = Objects.*WatershedBoundaries | logical(primarySegmentation);
        ObjectsLabeled = bwlabel(Objects);
        ObjectsLabeled = imfill(ObjectsLabeled, 'holes');
    else
        ObjectsLabeled = bwlabel(primarySegmentation);
    end
    
    props = regionprops(ObjectsLabeled, 'Area');
    ObjectsLabeled = ObjectsLabeled .* ismember(ObjectsLabeled, find([props.Area] >= p.Results.AreaThreshold));
    ObjectsLabeled = bwlabel(ObjectsLabeled);
end