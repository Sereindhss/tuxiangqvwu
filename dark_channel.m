function dark = dark_channel(I, patchSize)
%DARK_CHANNEL Compute the dark channel of an RGB image.

    if nargin < 2 || isempty(patchSize)
        patchSize = 15;
    end

    if ndims(I) == 2
        I = repmat(I, [1 1 3]);
    end
    I = im2double(I);
    minChannel = min(I, [], 3);
    se = strel('square', patchSize);
    dark = imerode(minChannel, se);
end
