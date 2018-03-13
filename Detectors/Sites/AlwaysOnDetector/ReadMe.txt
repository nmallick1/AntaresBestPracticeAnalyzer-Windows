This Detector checks to see if you have enabled AlwaysOn Setting. The WebApplicaiton process will be shutdown if there are no active users for 20 minutes to save resources. The new request after this timeout might be slower as the runtime has to start a new process.

If AlwaysOn is enabled then idle timeout will not affect the process and increases applicaiton responsivenes.