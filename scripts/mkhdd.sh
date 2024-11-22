if [ $# -ne 2 ]; then
    exit 1
fi

SOURCE_DIR="$1"
IMAGE_FILE="$2"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

dd if=/dev/zero of=$IMAGE_FILE bs=1M count=0 seek=64 status=none
sgdisk $IMAGE_FILE -n 1:2048 -t 1:ef00
mformat -i $IMAGE_FILE@@1M

mmd -i $IMAGE_FILE@@1M ::/EFI ::/EFI/BOOT
mcopy -i $IMAGE_FILE@@1M $SOURCE_DIR/* ::
mcopy -i $IMAGE_FILE@@1M $SOURCE_DIR/EFI/BOOT/* ::/EFI/BOOT
