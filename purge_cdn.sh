#!/bin/bash

# 遍历从1到25的数字
for i in {1..25}
do
    echo "Purging cache for image $i.jpeg..."
    curl -X GET "https://purge.jsdelivr.net/gh/kyriezhang/Gallery-competition@master/img/Photo/$i.jpeg"
    echo -e "\n"
    # 添加短暂延迟，避免请求过快
    sleep 1
done

# 刷新其他特殊命名的图片
for img in "MC" "chris" "spike" "xia"
do
    echo "Purging cache for image $img.jpeg..."
    curl -X GET "https://purge.jsdelivr.net/gh/kyriezhang/Gallery-competition@master/img/Photo/$img.jpeg"
    echo -e "\n"
    sleep 1
done 