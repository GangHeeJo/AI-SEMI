# NRV(Neuro Reality Vision) 공식 GitHub 조사 (2026-10-05)

조직: https://github.com/nrvcorp (2022-12 생성, 공개 저장소 4개, 라이선스 표기 없음 -> 코드 재사용/재배포 금지, 읽고 참고만).
- `DELTA_SDK`: Linux용 DVS Viewer 데모(바이너리 위주), README 14 KB. 설정 파일 Delta_01_1000FPS.txt / Delta_10_2000FPS.txt(README는 "300 Frame Rate"라고 표기해 불일치).
- `embeddedsw` (C/C++, 1,887 파일, 대부분 예제 이미지/NPU 시험 벡터): Xilinx FPGA 기반 참조 플랫폼.
  1. `1.Single_DVS`: 펌웨어(MIPI 수신 xmipi, Si5324 클럭 칩 드라이버, 센서 레지스터 설정 sensor_cfgs.c, JTAG/SD 부팅) + 호스트(C++, PCIe XDMA DMA 스트리밍, circular FIFO).
  2. `2.Dual_DVS`: DVS 2개 호스트 코드(DVS.cpp, CIS.cpp, PCIe.hpp). 옵션: -c CIS 스트리밍, -d DVS 스트리밍, -x 프레임 스킵 검사, -s CIS+DVS 동시, -w 원시 데이터 저장, -r DVS ROI(바운딩 박스), -b DVS에서 추정한 ROI를 CIS 영상에 표시. ROI_THRESH, ROI_INFLATION, CIS_DVS_OFFSET/SCALE(DVS 시야를 CIS 프레임에 수동 정렬).
  3. `3.CIS_DVS`: DVS + CIS 동시 스트리밍(같은 구조).
  4. `4.CIS_DVS_NPU`: Tiny-YOLOv3 NPU 시험 벡터(CONV 레이어별 ifm/weight/ofm, .coe/.hex), darknet, yolov3-tiny-aix2022.cfg, CIS_DVS 보드와 NPU 보드 펌웨어 -> DVS ROI + 객체 검출 파이프라인.
- 공식 호스트 코드(`3.CIS_DVS/host/src/DVS.cpp`)가 말하는 FPGA 출력 형식: **프레임당 8바이트 헤더(바이트 0~3 = 타임스탬프 uint32, 4~7 = 프레임 번호) + 픽셀당 2비트(0 = 이벤트 없음, 1 = ON, 2 = OFF)**. 즉 FPGA 경로는 센서의 이벤트 패킷을 프레임 단위 2비트 맵으로 바꿔 PCIe로 보냄(프레임당 타임스탬프 하나라는 3차 Q&A 설명과 일치). 원시 .dvs(MIPI 그룹 AER)와는 별개 표현이며, 원시 .dvs에서 현수가 역공학한 극성 규약(0 = ON)과 호스트 코드의 1 = ON은 서로 다른 계층의 규약임. 극성 일관성 분석은 부호 규약에 무관.
- 해석: NRV의 공개 소프트웨어는 센서 스트리밍, DVS 기반 ROI, CIS 동시 촬영, NPU 객체 검출에 초점이 있고, 월드 좌표 변환/매핑 블록은 없음(= 이 대회 과제가 메우는 부분). 자율주행/스마트 팩토리 통합 SDK라는 표현은 공개 저장소 내용으로는 확인되지 않음(데모 뷰어와 참조 임베디드 코드).
