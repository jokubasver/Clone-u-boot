#!/bin/sh

#
# fusing script for ODROID-GO2 based on Rockchip RK3326
# 支持写入SD卡和IMG文件
#

IDBLOADER=idbloader.img
UBOOT=uboot.img
TRUST=trust.img

show_usage() {
    echo "Usage:"
    echo "  ./sd_fusing.sh <device>          # 写入SD卡设备 (如 /dev/sdb)"
    echo "  ./sd_fusing.sh -i <image_file>   # 写入IMG文件"
    echo ""
    echo "Examples:"
    echo "  ./sd_fusing.sh /dev/sdb          # 写入SD卡"
    echo "  ./sd_fusing.sh -i system.img     # 写入IMG文件"
}

check_files() {
    if [ ! -f "$IDBLOADER" ]; then
        echo "错误: 找不到 $IDBLOADER"
        exit 1
    fi
    if [ ! -f "$UBOOT" ]; then
        echo "错误: 找不到 $UBOOT"
        exit 1
    fi
    if [ ! -f "$TRUST" ]; then
        echo "错误: 找不到 $TRUST"
        exit 1
    fi
    echo "✓ 所有必要的镜像文件都存在"
}

fuse_to_device() {
    local device=$1
    echo "正在写入设备: $device"
    
    # 安全检查
    if [ ! -b "$device" ]; then
        echo "错误: $device 不是块设备"
        exit 1
    fi
    
    # 确认操作
    echo "警告: 这将擦除设备 $device 上的所有数据!"
    read -p "确定要继续吗? (y/N): " confirm
    case $confirm in
        [yY]|[yY][eE][sS])
            ;;
        *)
            echo "操作已取消"
            exit 0
            ;;
    esac
    
    echo "开始写入引导加载程序..."
    
    sudo dd if=$IDBLOADER of=$device conv=fsync bs=512 seek=64
    if [ $? -ne 0 ]; then
        echo "错误: 写入 idbloader 失败"
        exit 1
    fi
    echo "✓ idbloader 写入完成"
    
    sudo dd if=$UBOOT of=$device conv=fsync bs=512 seek=16384
    if [ $? -ne 0 ]; then
        echo "错误: 写入 uboot 失败"
        exit 1
    fi
    echo "✓ uboot 写入完成"
    
    sudo dd if=$TRUST of=$device conv=fsync bs=512 seek=24576
    if [ $? -ne 0 ]; then
        echo "错误: 写入 trust 失败"
        exit 1
    fi
    echo "✓ trust 写入完成"
    
    sync
    echo "✓ 所有数据已同步"
    
    # 只有物理设备才弹出
    if [ -b "$device" ] && [ "$device" != "$img_file" ]; then
        sudo eject $device
        echo "✓ 设备已弹出"
    fi
    
    echo "✅ 写入完成!"
}

fuse_to_image() {
    local img_file=$1
    
    echo "正在写入镜像文件: $img_file"
    
    # 检查镜像文件是否存在且可写
    if [ ! -f "$img_file" ]; then
        echo "错误: 镜像文件 $img_file 不存在"
        exit 1
    fi
    
    if [ ! -w "$img_file" ]; then
        echo "错误: 镜像文件 $img_file 不可写"
        exit 1
    fi
    
    # 将镜像文件作为loop设备挂载
    echo "挂载镜像文件..."
    local loop_device=$(sudo losetup -f)
    sudo losetup -P $loop_device "$img_file"
    
    if [ $? -ne 0 ]; then
        echo "错误: 挂载镜像文件失败"
        exit 1
    fi
    
    # 使用相同的写入逻辑
    fuse_to_device $loop_device
    
    # 卸载loop设备
    echo "卸载镜像文件..."
    sudo losetup -d $loop_device
    
    echo "✅ 镜像文件写入完成!"
}

# 主程序
main() {
    echo "ODROID-GO2 RK3326 引导加载程序写入工具"
    echo "======================================"
    
    # 检查必要的文件
    check_files
    
    case $1 in
        -i|--image)
            if [ -z "$2" ]; then
                echo "错误: 请指定镜像文件名"
                show_usage
                exit 1
            fi
            fuse_to_image "$2"
            ;;
        -h|--help)
            show_usage
            ;;
        "")
            echo "错误: 请指定目标设备或镜像文件"
            show_usage
            exit 1
            ;;
        *)
            # 默认情况下，认为是设备路径
            fuse_to_device "$1"
            ;;
    esac
}

# 运行主程序
main "$@"