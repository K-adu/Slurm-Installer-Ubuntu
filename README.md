# Slurm Installer Script Documentation

## Installation

Paste the script content into the file and save it (`Ctrl + O`, then `Enter`) and exit (`Ctrl + X`).

### 1. **Make the Script Executable:**

```bash
chmod +x slurm_installer.sh
```

## Usage

Run the script with `sudo` to ensure it has the necessary permissions to install packages and configure services.

```bash
sudo ./slurm_installer.sh
```

## Interactive Prompts

The script will guide you through several prompts:

1. **Slurm Version:**
   * **Prompt:** `Enter the Slurm version you want to install (e.g., 24.05.5):`
   * **Default:** `24.05.5`
   * **Behavior:** If the entered version is unavailable, the script falls back to the default version.

2. **Installation Prefix:**
   * **Prompt:** `Enter installation prefix [ /opt/slurm ]:`
   * **Default:** `/opt/slurm`
   * **Behavior:** Press `Enter` to accept the default or input a custom directory.

3. **Slurm User:**
   * **Prompt:** `Enter Slurm user [ ubuntu ]:`
   * **Default:** `ubuntu`
   * **Behavior:** Press `Enter` to accept the default or specify a different user.

4. **Slurm Group:**
   * **Prompt:** `Enter Slurm group [ ubuntu ]:`
   * **Default:** `ubuntu`
   * **Behavior:** Press `Enter` to accept the default or specify a different group.

## Script Workflow

1. **Dependency Installation:** Updates the package list and installs necessary build dependencies and packages.

2. **Munge Setup:** Installs and configures Munge for authentication, with fallback methods if the primary setup fails.

3. **User and Group Creation:** Creates the specified Slurm user and group if they do not already exist.

4. **Slurm Download and Installation:** Downloads the specified Slurm version, compiles it using all available CPU cores, and installs it to the specified prefix.

5. **Configuration:**
   * Creates necessary directories for Slurm.
   * Generates a basic `slurm.conf` based on the system's CPU and memory.

6. **Environment Setup:** Updates the user's `.bashrc` to include Slurm binaries in the `PATH`.

7. **Systemd Services:** Sets up `slurmctld` and `slurmd` as systemd services, enabling and starting them.

8. **Cleanup:** Removes temporary installation files.

9. **Service Status:** Displays the status of the Slurm services to confirm successful installation.

## Configuration

### `slurm.conf`

The script generates a basic `slurm.conf` located at `/etc/slurm/slurm.conf`. This configuration includes:

* **Cluster Name:** `single_machine_cluster`
* **Controller Host:** `localhost`
* **Ports:** `6817` for `slurmctld` and `6818` for `slurmd`
* **User:** Specified Slurm user (default: `ubuntu`)
* **Spool Directories:** `/var/spool/slurm/slurmd` and `/var/spool/slurm/slurmctld`
* **Compute Node Configuration:** Reflects the system's CPU count and total memory.
* **Partition Configuration:** A default partition named `single_partition`.

## Customization

After installation, you can further customize `slurm.conf` based on your cluster's requirements. Refer to the Slurm Documentation for detailed configuration options.

## Post-Installation Steps

1. **Reload Shell Configuration:**
If you opened a new terminal session, the Slurm binaries should already be in your `PATH`. If not, you can manually source your `.bashrc`:

```bash
source ~/.bashrc
```

2. **Verify Installation:**
Check the status of Slurm services:

```bash
sudo systemctl status slurmctld
sudo systemctl status slurmd
```

You can also use Slurm commands like `sinfo` or `squeue` to verify functionality:

```bash
sinfo
squeue
```

3. **Firewall Configuration (If Applicable):**
If you plan to use Slurm across multiple nodes, ensure that the necessary ports (`6817` and `6818`) are open.

```bash
sudo ufw allow 6817/tcp
sudo ufw allow 6818/tcp
```

## Troubleshooting

* **Munge Setup Failures:**
   * Ensure that Munge is properly installed and its key is correctly generated.
   * Verify permissions of `/etc/munge/munge.key` (`chown munge:munge /etc/munge/munge.key` and `chmod 400 /etc/munge/munge.key`).
* **Service Issues:**
   * Check logs for `slurmctld` and `slurmd` located in `/var/log/slurm/`.
   * Ensure that the Slurm user and group have the correct permissions on Slurm directories.
* **Slurm Commands Not Found:**
   * Ensure that the installation prefix is correctly added to your `PATH`. Restart your terminal or source your `.bashrc`:

```bash
source ~/.bashrc
```

* **Compilation Errors:**
   * Verify that all build dependencies are installed.
   * Ensure that your system meets the minimum requirements for building Slurm.

## Contributing

Contributions are welcome! If you encounter issues or have suggestions for improvements, feel free to open an issue or submit a pull request.
