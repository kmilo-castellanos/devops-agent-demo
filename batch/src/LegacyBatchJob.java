import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Properties;

/**
 * Job batch "legado": lee un CSV de pedidos (id,cliente,monto), calcula totales
 * y escribe un resumen. Toda su configuración vive en batch.properties.
 *
 * Uso: java LegacyBatchJob /opt/batch/config/batch.properties
 */
public class LegacyBatchJob {

    private static void log(String level, String msg) {
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        System.out.println(ts + " " + level + " [LegacyBatchJob] " + msg);
    }

    public static void main(String[] args) throws Exception {
        String configPath = args.length > 0 ? args[0] : "/opt/batch/config/batch.properties";
        log("INFO", "Job started, config=" + configPath);

        Properties cfg = new Properties();
        try (FileInputStream in = new FileInputStream(configPath)) {
            cfg.load(in);
        }

        String inputFile = cfg.getProperty("input.file");
        String outputDir = cfg.getProperty("output.dir", "/opt/batch/out");
        int maxRecords = Integer.parseInt(cfg.getProperty("max.records", "1000"));
        log("INFO", "input.file=" + inputFile + " output.dir=" + outputDir + " max.records=" + maxRecords);

        double total = 0;
        int count = 0;
        try (BufferedReader reader = new BufferedReader(new FileReader(inputFile))) {
            String line;
            while ((line = reader.readLine()) != null && count < maxRecords) {
                if (line.startsWith("id,")) {
                    continue; // cabecera
                }
                String[] parts = line.split(",");
                total += Double.parseDouble(parts[2]);
                count++;
            }
        } catch (IOException e) {
            log("ERROR", "Batch aborted while reading input file " + inputFile);
            throw e;
        }

        File dir = new File(outputDir);
        dir.mkdirs();
        File out = new File(dir, "summary.txt");
        try (PrintWriter w = new PrintWriter(new FileWriter(out))) {
            w.println("records=" + count);
            w.println("total=" + String.format("%.2f", total));
        }
        log("INFO", "Job finished OK: " + count + " records, total=" + String.format("%.2f", total));
    }
}
