const myanmarOffset=Duration(hours:6,minutes:30);
DateTime myanmarTime(DateTime instant)=>instant.toUtc().add(myanmarOffset);
DateTime myanmarWallToUtc(DateTime wall)=>DateTime.utc(wall.year,wall.month,wall.day,wall.hour,wall.minute,wall.second).subtract(myanmarOffset);
