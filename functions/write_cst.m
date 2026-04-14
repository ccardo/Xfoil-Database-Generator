function success = write_cst(filepath, T, B)

    cst = [T(:)' B(:)'];

    try 
        fid = fopen(filepath, "w");
        fprintf(fid, "%.4f\n", cst);
        fclose(fid);
        success = true;
    catch
        success = false;
    end

end