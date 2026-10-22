function iq = load_cf32_iq(iqFile)
    % LOAD_CF32_IQ  Read an interleaved complex float32 (.cf32) IQ file.
    %
    % Little-endian float32 I0, Q0, I1, Q1, ... Returns a complex single
    % column vector.

    if ~isfile(iqFile)
        error(['IQ file not found: %s\n' ...
               'Place the DAB IQ file there or update iqFile in ' ...
               'generate_dab_tdoa_dataset.m (see README).'], iqFile);
    end

    fid = fopen(iqFile, 'rb');
    assert(fid ~= -1, 'Could not open IQ file: %s', iqFile);

    % A Git LFS pointer is a small text file instead of the IQ data.
    header = fread(fid, [1 40], '*char');
    if startsWith(header, 'version https://git-lfs')
        fclose(fid);
        error(['%s is a Git LFS pointer, not the IQ data. ' ...
               'Run "git lfs install" and "git lfs pull" first.'], iqFile);
    end
    frewind(fid);

    raw = fread(fid, 'float32=>single');
    fclose(fid);

    assert(~isempty(raw), 'IQ file is empty.');
    assert(mod(numel(raw),2)==0, 'Interleaved IQ file must contain even number of float32 values.');

    iq = raw(1:2:end) + 1j*raw(2:2:end);
    iq = iq(:);
end
