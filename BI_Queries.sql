--------------------------------------------------------------------- DA MANDARE SOLO UNA VOLTA ------------------------------------------------------------------------------------------------------------------------------------------
--- SISTEMO COLONNA DTAPPELLO , 
-- 1. Aggiungi una nuova colonna di tipo datetime
ALTER TABLE appelli ADD date_appello DATETIME;
-- 2. Aggiorna la nuova colonna con le date corrette
UPDATE appelli
   SET date_appello = CASE WHEN instr(appelli.dtappello, '/') = 0 
   THEN NULL ELSE strftime('%Y-%m-%d', printf('%04d-%02d-%02d', substr(appelli.dtappello, -4), 
   substr('0' || substr(appelli.dtappello, instr(appelli.dtappello, '/') + 1, 2), -2), 
   substr('0' || substr(appelli.dtappello, 1, instr(appelli.dtappello, '/') - 1), -2) ) ) END;

 ---- cambio formato data colonna dtappello in bos_denormalizzato
UPDATE bos_denormalizzato SET DtAppello = '20' || 
	substr(DtAppello, 7, 2) || '-' || 
	substr(DtAppello, 4, 2) || '-' || 
	substr(DtAppello, 1, 2);

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
   
---- Domanda 1: Distribuzione del numero degli studenti iscritti nei vari appelli, suddivisa per anni e per corso di laurea
SELECT strftime('%Y', date_appello) as anno,
       cds,
       count(studente) AS [numero studenti iscritti]
  FROM iscrizioni,
       appelli,
       cds
 WHERE iscrizioni.appcod = appelli.appcod AND 
       appelli.cdscod = cds.cdscod
 GROUP BY cds,
          strftime('%Y', date_appello) 
 ORDER BY strftime('%Y', date_appello);

-- Domanda 1 (bos_denormalizzato)
SELECT strftime('%Y', DtAppello) AS anno, 
	   CdS, 
	   count(Studente) as 'numero studenti iscritti'
  FROM bos_denormalizzato
  GROUP by CdS, 
		   anno
  ORDER by anno;

  
  
---- Domanda 2 , Top-10 degli esami più difficili suddivisi per corso di studi
SELECT cds, ad, Promossi, Iscritti, rapporto_promossi
FROM (
		SELECT cds.cds, ad.ad,
       sum(iscrizioni.Superamento) AS Promossi,
       count(iscrizioni.Iscrizione) AS Iscritti,
       round(CAST (sum(iscrizioni.Superamento) AS REAL) / count(iscrizioni.Iscrizione), 3) AS rapporto_promossi,
		row_number() OVER(PARTITION BY cds.cds ORDER BY CAST (sum(iscrizioni.Superamento) AS REAL) / count(iscrizioni.Iscrizione)) AS rank
  FROM ad JOIN appelli ON ad.adcod = appelli.adcod
       JOIN cds ON appelli.cdscod = cds.cdscod
       JOIN iscrizioni ON appelli.appcod = iscrizioni.appcod
 WHERE (strftime('%Y', date_appello) = '2016' AND 
        strftime('%m', date_appello) >= '10' OR 
        strftime('%Y', date_appello) = '2017' AND 
        strftime('%m', date_appello) <= '10') 
GROUP BY Cds, ad
HAVING count(ad.ad) >= 10 
) ranked
WHERE rank <= 10
ORDER BY Cds, rapporto_promossi;

-- Domanda 2 (denormalizzato)
SELECT CdS, AD, Promossi, Iscritti, rapporto_promossi
FROM (
		SELECT CdS, AD,
       SUM(Superamento) AS Promossi,
       COUNT(Iscrizione) AS Iscritti,
       ROUND(CAST (SUM(Superamento) AS REAL) / COUNT(Iscrizione), 3) AS rapporto_promossi,
		ROW_NUMBER() OVER(PARTITION BY CdS ORDER BY CAST (SUM(Superamento) AS REAL) / COUNT(Iscrizione)) AS rank
  FROM bos_denormalizzato
 WHERE (strftime('%Y', DtAppello) = '2016' AND 
        strftime('%m', DtAppello) >= '10' OR 
        strftime('%Y', DtAppello) = '2017' AND 
        strftime('%m', DtAppello) <= '10') 
GROUP BY CdS, AD
HAVING COUNT(AD) >= 10
) ranked
WHERE rank <= 10
ORDER BY CdS, rapporto_promossi;
 
 
 
---- Domanda 3: Individuazione dei corsi di laurea ad elevato tasso di commitment
WITH AppelliDiversiStessaData AS (
  SELECT cdscod, COUNT(*) AS GiorniConPiuAppelli
  FROM (
	SELECT cdscod, date_appello
	FROM (
    SELECT DISTINCT date_appello, adcod, cdscod
    FROM appelli
) 
	GROUP BY cdscod, date_appello
	HAVING COUNT(DISTINCT adcod) > 1
  )
	GROUP BY cdscod
)
, TotaleAppelli AS (
  SELECT cdscod, COUNT(DISTINCT date_appello) AS TotGiorni
  FROM (
    SELECT DISTINCT date_appello, adcod, cdscod
    FROM appelli
) 
  GROUP BY cdscod
)
SELECT cds.cds, adsd.GiorniConPiuAppelli, t.TotGiorni, round((1.0 * adsd.GiorniConPiuAppelli) / t.TotGiorni, 3) AS TassoCommitment
FROM AppelliDiversiStessaData adsd, TotaleAppelli t, cds
WHERE adsd.cdscod = t.cdscod AND adsd.cdscod = cds.cdscod
ORDER by TassoCommitment DESC;

-- Domanda 3 (bos_denormalizzato)
WITH AppelliDiversiStessaData AS (
  SELECT CdSCod, COUNT(*) AS GiorniConPiuAppelli
  FROM (
	SELECT CdsCod, DtAppello
	FROM (
    SELECT DISTINCT DtAppello, AdCod, CdsCod
    FROM bos_denormalizzato
) 
	GROUP BY CdsCod, DtAppello
	HAVING COUNT(DISTINCT AdCod) > 1
  )
	GROUP BY CdsCod
)
, TotaleAppelli AS (
  SELECT CdsCod, COUNT(DISTINCT DtAppello) AS TotGiorni
  FROM (
    SELECT DISTINCT DtAppello, AdCod, CdsCod
    FROM bos_denormalizzato
) 
  GROUP BY CdsCod
)
SELECT CdS, adsd.GiorniConPiuAppelli, t.TotGiorni, round((1.0 * adsd.GiorniConPiuAppelli) / t.TotGiorni, 3) AS TassoCommitment
FROM AppelliDiversiStessaData adsd, TotaleAppelli t, bos_denormalizzato
WHERE adsd.CdsCod = t.CdsCod AND adsd.CdsCod = bos_denormalizzato.CdsCod
GROUP by CdS
ORDER by TassoCommitment DESC;



---- Domanda 4: Individuazione della Top-3 degli esami con media voti maggiore e minore rispettivamente, calcolati per ogni singolo corso di studi
-- Top 3 media voti maggiore
WITH Classificati AS (
    SELECT appelli.cdscod, appelli.adcod, round(AVG(iscrizioni.Voto), 3) AS MediaVoti, ROW_NUMBER() OVER (PARTITION BY appelli.cdscod ORDER BY AVG(iscrizioni.Voto) DESC
        ) as Rango
    FROM iscrizioni 
    JOIN appelli ON iscrizioni.appcod = appelli.appcod
    WHERE iscrizioni.Superamento = 1 AND iscrizioni.Voto is not null
    GROUP BY appelli.cdscod, appelli.adcod
), CdsAdCount AS (
    SELECT cdscod, COUNT(DISTINCT adcod) AS AdCount
    FROM appelli
    GROUP BY cdscod
    HAVING COUNT(DISTINCT adcod) >= 6
)
SELECT cds, ad, c.MediaVoti
FROM Classificati c, cds, ad
JOIN CdsAdCount cac ON c.cdscod = cac.cdscod
WHERE c.Rango <= 3 AND c.cdscod = cds.cdscod AND c.adcod = ad.adcod
ORDER BY c.cdscod, c.Rango;

-- Top 3 media voti minore
WITH Classificati AS (
    SELECT appelli.cdscod, appelli.adcod, round(AVG(iscrizioni.Voto), 3) AS MediaVoti, ROW_NUMBER() OVER (PARTITION BY appelli.cdscod ORDER BY AVG(iscrizioni.Voto) ASC
        ) as Rango
    FROM iscrizioni JOIN appelli ON iscrizioni.appcod = appelli.appcod
    WHERE iscrizioni.Superamento = 1 
	AND iscrizioni.Voto is not null
    GROUP BY appelli.cdscod, appelli.adcod
), CdsAdCount AS (
    SELECT cdscod, COUNT(DISTINCT adcod) AS AdCount
    FROM appelli
    GROUP BY cdscod
    HAVING COUNT(DISTINCT adcod) >= 6
)
SELECT cds, ad, c.MediaVoti
FROM Classificati c, cds, ad
JOIN CdsAdCount cac ON c.cdscod = cac.cdscod
WHERE c.Rango <= 3 AND c.cdscod = cds.cdscod AND c.adcod = ad.adcod
ORDER BY c.cdscod, c.Rango;


-- Domanda 4 (bos_denormalizzato)
-- Top 3 con media voti maggiore
WITH Classificati AS (
    SELECT CdSCod, AdCod, AVG(Voto) AS MediaVoti, ROW_NUMBER() OVER (PARTITION BY CdSCod ORDER BY AVG(Voto) DESC
        ) AS Rango
    FROM bos_denormalizzato
    WHERE Superamento = 1 AND Voto IS NOT NULL
    GROUP BY CdSCod, AdCod
), CdsAdCount AS (
    SELECT CdSCod, COUNT(DISTINCT AdCod) AS AdCount
    FROM bos_denormalizzato
    GROUP BY CdSCod
    HAVING COUNT(DISTINCT AdCod) >= 6
)
SELECT c.CdSCod, c.AdCod, c.MediaVoti
FROM Classificati c
JOIN CdsAdCount cac ON c.CdSCod = cac.CdSCod
WHERE c.Rango <= 3
ORDER BY c.CdSCod, c.Rango;

-- Top 3 con media voti minore
WITH Classificati AS (
    SELECT CdSCod, AdCod, AVG(Voto) AS MediaVoti, ROW_NUMBER() OVER (PARTITION BY CdSCod ORDER BY AVG(Voto) ASC
        ) AS Rango
    FROM bos_denormalizzato
    WHERE Superamento = 1 AND Voto IS NOT NULL
    GROUP BY CdSCod, AdCod
), CdsAdCount AS (
    SELECT CdSCod, COUNT(DISTINCT AdCod) AS AdCount
    FROM bos_denormalizzato
    GROUP BY CdSCod
    HAVING COUNT(DISTINCT AdCod) >= 6
)
SELECT c.CdSCod, c.AdCod, c.MediaVoti
FROM Classificati c
JOIN CdsAdCount cac ON c.CdSCod = cac.CdSCod
WHERE c.Rango <= 3
ORDER BY c.CdSCod, c.Rango;




---- Domanda 5: Distribuzione degli studenti “fast&furious” per corso di studi
WITH Media as (
	SELECT cdscod, studente, avg(voto) as MediaEsami
	FROM iscrizioni, appelli
	WHERE iscrizioni.appcod = appelli.appcod AND Superamento == '1' AND voto is NOT NULL
	group by studente
	HAVING count(studente) > 3
	)
, Periodo as (
	SELECT cdscod, studente, (JULIANDAY(MAX(date_appello)) - JULIANDAY(MIN(date_appello))) AS PeriodoAttività
	FROM iscrizioni, appelli
	WHERE iscrizioni.appcod = appelli.appcod AND (Superamento == '1' or Insufficienza == '1')
	GROUP BY studente
)
SELECT cds.cds, m.studente, MediaEsami, PeriodoAttività, round((1.0 * m.MediaEsami) / p.PeriodoAttività, 3) AS TassoFastAndFurious
FROM Media m, Periodo p, cds
WHERE m.studente = p.studente AND cds.cdscod = p.cdscod AND TassoFastAndFurious NOT NULL
ORDER by cds.cds ASC, TassoFastAndFurious DESC;

-- Domanda 5 (bos_denormalizzato)
WITH Media as (
	SELECT CdSCod, Studente, avg(Voto) as MediaEsami
	FROM bos_denormalizzato
	WHERE Superamento == '1' AND Voto is NOT NULL
	group by Studente
	HAVING count(Studente) > 3
	)
, Periodo as (
	SELECT CdSCod, Studente, (JULIANDAY(MAX(DtAppello)) - JULIANDAY(MIN(DtAppello))) AS PeriodoAttività
	FROM bos_denormalizzato
	WHERE Superamento == '1' or Insufficienza == '1'
	GROUP BY Studente
)
SELECT CdS, m.Studente, MediaEsami, PeriodoAttività, (1.0 * m.MediaEsami) / p.PeriodoAttività AS TassoFastAndFurious
FROM Media m, Periodo p, bos_denormalizzato
WHERE m.Studente = p.Studente AND bos_denormalizzato.CdSCod = p.CdSCod AND TassoFastAndFurious NOT NULL
ORDER by CdS ASC, TassoFastAndFurious DESC;



---- Domanda 6: Top-3 degli esami “trial&error”, ovvero esami che richiedono il maggior numero di tentativi prima del superamento.
WITH superamenti AS (
    SELECT cds.cds, studente, ad.ad
    FROM iscrizioni
    JOIN appelli ON iscrizioni.appcod = appelli.appcod
    JOIN cds ON appelli.cdscod = cds.cdscod
    JOIN ad ON appelli.adcod = ad.adcod
    WHERE Superamento = '1' AND Voto IS NOT NULL
)
, tentativi AS (
    SELECT cds.cds, iscrizioni.studente, ad.ad, COUNT(CASE WHEN Insufficienza = '1' THEN 1 END) AS bocciature
    FROM iscrizioni
    JOIN appelli ON iscrizioni.appcod = appelli.appcod
    JOIN cds ON appelli.cdscod = cds.cdscod
    JOIN ad ON appelli.adcod = ad.adcod
    WHERE Insufficienza = '1' AND
        studente IN (SELECT studente FROM superamenti)
    GROUP BY cds.cds, ad.ad, studente
)
SELECT cds, ad, TrialAndError
FROM (
    SELECT cds, ad, ROUND(AVG(bocciature), 3) AS TrialAndError, ROW_NUMBER() OVER (PARTITION BY cds ORDER BY AVG(bocciature) DESC) AS rank
    FROM tentativi
    GROUP BY cds, ad
) ranked
WHERE rank <= 3
ORDER BY cds, TrialAndError DESC;

-- Domanda 6 (bos_denormalizzato)
WITH superamenti AS (
    SELECT CdS, Studente, AD
    FROM bos_denormalizzato
    WHERE Superamento = '1' AND Voto IS NOT NULL
)
, tentativi AS (
    SELECT CdS, Studente, AD, COUNT(CASE WHEN Insufficienza = '1' THEN 1 END) AS bocciature
    FROM bos_denormalizzato
    WHERE Insufficienza = '1' AND
        Studente IN (SELECT Studente FROM superamenti)
    GROUP BY CdS, AD, Studente
)
SELECT CdS, AD, TrialAndError
FROM (
    SELECT CdS, AD, ROUND(AVG(bocciature), 3) AS TrialAndError, ROW_NUMBER() OVER (PARTITION BY CdS ORDER BY AVG(bocciature) DESC) AS rank
    FROM tentativi
    GROUP BY CdS, AD
) ranked
WHERE rank <= 3
ORDER BY CdS, TrialAndError DESC;


---- Domanda 7.1 a scelta: Identificazione della media voti degli studenti in base alla provenienza geografica
SELECT s.cittnaz, COUNT(DISTINCT s.studente) AS NumeroStudenti, round(AVG(i.Voto), 3) AS MediaVoti
FROM studenti s JOIN iscrizioni i ON s.studente = i.studente
JOIN appelli a ON i.appcod = a.appcod
WHERE i.Voto IS NOT NULL
GROUP BY s.cittnaz;

-- Domanda 7.1 (bos_denormalizzato)
SELECT cittnaz, count(distinct(studente)) as NumeroStudenti, round(avg(Voto), 3) as MediaVoti
FROM bos_denormalizzato
WHERE Voto is not null
GROUP BY cittnaz;

---- Domanda 7.2 a scelta: Confronto della media dei voti tra maschi e femmina nei vari gradi di corsi di studio (Triennale, Magistrale e Magistrale ciclo unico)
SELECT strftime('%m/%Y', a.date_appello) AS data, s.genere, c.tipocorso, ROUND(AVG(i.Voto), 3) AS media_voti
FROM iscrizioni i JOIN appelli a ON i.appcod = a.appcod
JOIN cds c ON a.cdscod = c.cdscod
JOIN studenti s ON i.studente = s.studente
WHERE i.Voto IS NOT NULL 
AND i.Superamento = 1
GROUP BY strftime('%m/%Y', a.date_appello), s.genere, c.tipocorso
ORDER BY strftime('%Y', a.date_appello), c.tipocorso;

---- Domanda 7.2 a scelta (bos_denormalizzato)
SELECT strftime('%m/%Y', DtAppello) AS data, StuGen AS genere, TipoCorso, ROUND(AVG(Voto), 2) AS media_voti
FROM bos_denormalizzato
WHERE Voto IS NOT NULL 
AND Superamento = 1
GROUP BY strftime('%m/%Y', DtAppello), StuGen, TipoCorso
ORDER BY  strftime('%Y', DtAppello), TipoCorso;
